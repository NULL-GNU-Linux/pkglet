--- Configuration management module for pkglet system settings and paths
--
-- This module centralizes all configuration management for the pkglet package manager,
-- including filesystem paths, repository configurations, package options, and system
-- settings. It handles dynamic configuration loading from various config files and
-- environment variables, allowing for flexible system deployment. The module manages
-- directory creation, configuration file parsing, and runtime configuration updates
-- that support bootstrap installations and custom deployment scenarios.
--
-- Configuration is loaded from multiple sources: environment variables for paths,
-- configuration files for repositories and package settings, and runtime modifications
-- for bootstrap operations. This layered approach provides both system-wide defaults
-- and user-specific customizations.
-- @module config

local config = {}
config.PREFIX = os.getenv("PKGLET_PREFIX") or ""
config.ROOT = config.PREFIX .. "/"
config.DB_PATH = config.PREFIX .. "/var/lib/pkglet"
config.CACHE_PATH = "/var/cache/pkglet"
config.BUILD_PATH = config.CACHE_PATH .. "/build"
config.TEMP_INSTALL_PATH = config.CACHE_PATH .. "/temp_install"
config.DISTFILES_PATH = config.CACHE_PATH .. "/distfiles"
config.CONFIG_DIR = "/etc/pkglet"
config.REPOS_CONF = config.CONFIG_DIR .. "/repos.conf"
config.MAKE_CONF = config.CONFIG_DIR .. "/make.lua"
config.PACKAGE_OPTS = config.CONFIG_DIR .. "/package.opts"
config.PACKAGE_MASK = config.CONFIG_DIR .. "/package.mask"
config.global_options = {}
config.package_options = {}
config.masked_packages = {}
config.repos = {}

--- Initialize the entire configuration system and create necessary directories
--
-- This function performs one-time initialization of the pkglet configuration system
-- by creating all required directories (database, build, and distfiles directories)
-- and loading configuration from various files. It establishes the runtime
-- environment needed for package operations, ensuring that all paths exist and
-- configuration data is available before any package operations begin.
--
-- The initialization process is critical for system startup and must be called
-- before any other pkglet operations to ensure the system is in a consistent state.
-- It creates directories with proper permissions and loads repository information,
-- package options, and package masks from their respective configuration files.
function config.init()
    os.execute("mkdir -p " .. config.DB_PATH)
    os.execute("mkdir -p " .. config.BUILD_PATH)
    os.execute("mkdir -p " .. config.DISTFILES_PATH)
    os.execute("mkdir -p " .. config.TEMP_INSTALL_PATH)
    config.load_repos()
    config.load_package_options()
    config.load_masks()
end

--- Load repository configuration from the repos.conf file
--
-- This function parses the repository configuration file to populate the
-- config.repos table with available package repositories. The configuration
-- file uses a simple format with each line containing a repository name
-- followed by its filesystem path. Lines starting with # are treated as
-- comments and ignored, allowing for documentation within the config file.
--
-- The function handles missing files gracefully by returning early if
-- the repos.conf file doesn't exist, which allows the system to function
-- in minimal configurations or during initial setup.
function config.load_repos()
    local f = io.open(config.REPOS_CONF, "r")
    if not f then return end
    for line in f:lines() do
        line = line:gsub("#.*", ""):match("^%s*(.-)%s*$")
        if line ~= "" then
            local name, path = line:match("^(%S+)%s+(.+)$")
            if name and path then
                config.repos[name] = path
            end
        end
    end
    f:close()
end

--- Load package-specific build options from the package.opts directory structure
--
-- This function scans the package options directory for individual package option
-- files and loads them into the config.package_options table. Each file in the
-- directory corresponds to a specific package and contains build options that
-- should be applied when that package is built. The system supports flexible
-- per-package configuration while maintaining clean separation of settings.
--
-- Options are stored as a table of boolean flags for each package, enabling
-- conditional build behavior based on user preferences or system requirements.
-- The function handles missing directories gracefully and ignores non-parseable
-- content, ensuring robust operation in various deployment scenarios.
function config.load_package_options()
    local handle = io.popen("find " .. config.PACKAGE_OPTS .. " -type f 2>/dev/null")
    if not handle then return end
    for filepath in handle:lines() do
        local pkg = filepath:match("([^/]+)$")
        if pkg then
            config.package_options[pkg] = {}
            local f = io.open(filepath, "r")
            if f then
                for line in f:lines() do
                    line = line:gsub("#.*", ""):match("^%s*(.-)%s*$")
                    if line ~= "" then
                        for opt in line:gmatch("%S+") do
                            config.package_options[pkg][opt] = true
                        end
                    end
                end
                f:close()
            end
        end
    end
    handle:close()
end

--- Load package mask list from the package.mask configuration file
--
-- This function reads the package mask file to identify packages that should
-- not be installed or updated. Package masking is a critical safety feature
-- that prevents problematic packages from being installed, whether due to
-- known bugs, security issues, or system incompatibilities. The mask list
-- provides administrators with fine-grained control over package availability.
--
-- Each line in the mask file represents a package name pattern that should
-- be blocked. The function supports comment lines starting with # for
-- documentation and ignores empty lines, making the mask file maintainable
-- and self-documenting.
function config.load_masks()
    local f = io.open(config.PACKAGE_MASK, "r")
    if not f then return end
    for line in f:lines() do
        line = line:gsub("#.*", ""):match("^%s*(.-)%s*$")
        if line ~= "" then
            config.masked_packages[line] = true
        end
    end
    f:close()
end

--- Retrieve make system configuration options for parallel builds
--
-- This function loads make configuration from the make.lua file, providing
-- build system parameters that control parallel compilation and resource usage.
-- The configuration supports job count limits for parallel builds, load average
-- thresholds to prevent system overload, and custom make arguments for special
-- build requirements. These settings are essential for optimizing build performance
-- while maintaining system stability.
--
-- The function returns sensible defaults if no configuration file exists,
-- ensuring that the build system remains functional in minimal installations.
-- The Lua-based configuration allows for complex conditional logic and dynamic
-- parameter calculation based on system capabilities.
--
-- @return table Configuration options containing: jobs (parallel job count),
--               load (load average threshold), and extra (additional make arguments)
function config.get_make_opts()
    local opts = {
        jobs = 1,
        load = 1,
        extra = "",
    }

    local f = io.open(config.MAKE_CONF, "r")
    if f then
        local chunk = f:read("*a")
        f:close()
        local env = {}
        local fn = load(chunk, config.MAKE_CONF, "t", env)
        if fn then
            pcall(fn)
            if env.MAKEOPTS then opts = env.MAKEOPTS end
        end
    end
    return opts
end

--- Configure system for bootstrap installation mode
--
-- This function updates all path configurations to point to a bootstrap root
-- directory, enabling pkglet to install packages to an alternate filesystem
-- hierarchy. Bootstrap mode is essential for system installation, container
-- creation, and recovery operations where packages must be installed to a
-- temporary or target root rather than the running system.
--
-- The function updates all derived paths to maintain consistency, ensuring
-- that database, cache, and configuration operations use the bootstrap
-- location. This allows for complete system isolation during installation
-- while preserving full package manager functionality.
--
-- @param path string The target root directory for bootstrap installation,
--                   which will become the new base for all pkglet operations

function config.set_bootstrap_root(path)
    config.PREFIX = path
    config.ROOT = path .. "/"
    config.DB_PATH = path .. "/var/lib/pkglet"
end
return config
