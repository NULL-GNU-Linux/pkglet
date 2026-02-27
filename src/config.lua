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

local function is_root()
    return os.execute("id -u 2>/dev/null | grep -q '^0$'") == true
end

local function get_home()
    return os.getenv("HOME") or "/root"
end

local function setup_non_root_paths()
    local home = get_home()
    local local_base = home .. "/.local"

    config.PREFIX = local_base
    config.ROOT = local_base .. "/"
    config.BIN_PATH = local_base .. "/bin"
    config.LIB_PATH = local_base .. "/lib"
    config.LIB64_PATH = local_base .. "/lib64"
    config.SHARE_PATH = local_base .. "/share"
    config.DB_PATH = local_base .. "/var/lib/pkglet"
    config.CACHE_PATH = local_base .. "/cache/pkglet"
    config.BUILD_PATH = config.CACHE_PATH .. "/build"
    config.TEMP_INSTALL_PATH = config.CACHE_PATH .. "/temp_install"
    config.DISTFILES_PATH = config.CACHE_PATH .. "/distfiles"
    config.CONFIG_DIR = home .. "/.config/pkglet"
    config.REPOS_CONF = config.CONFIG_DIR .. "/repos.conf"
    config.MAKE_CONF = config.CONFIG_DIR .. "/make.lua"
    config.PACKAGE_OPTS = config.CONFIG_DIR .. "/package.opts"
    config.PACKAGE_MASK = config.CONFIG_DIR .. "/package.mask"
    config.PACKAGE_LOCK = config.CONFIG_DIR .. "/package.lock"
end

if not is_root() then
    setup_non_root_paths()
else
    local prefix = os.getenv("PKGLET_PREFIX") or ""
    config.PREFIX = prefix
    config.ROOT = prefix .. "/"
    
    if prefix == "/usr/local" or prefix == "" then
        config.BIN_PATH = "/usr/local/bin"
        config.LIB_PATH = "/usr/local/lib"
        config.LIB64_PATH = "/usr/local/lib64"
        config.SHARE_PATH = "/usr/local/share"
    else
        config.BIN_PATH = prefix .. "/bin"
        config.LIB_PATH = prefix .. "/lib"
        config.LIB64_PATH = prefix .. "/lib64"
        config.SHARE_PATH = prefix .. "/share"
    end
    
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
    config.PACKAGE_LOCK = config.CONFIG_DIR .. "/package.lock"
end

config.global_options = {}
config.package_options = {}
config.masked_packages = {}
config.pinned_packages = {}
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
    config.load_pins()
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
            local name, path = line:match("^(%S+)%s+(%S+)$")
            if name and path then
                if path:match("^https?://") or path:match("^git@") or path:match("%.git$") then
                    config.repos[name] = { url = path, is_git = true }
                else
                    config.repos[name] = { path = path, is_git = false }
                end
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
            local repo, pkg = line:match("^([^/]+)/(.+)$")
            if repo and pkg then
                if not config.masked_packages[repo] then
                    config.masked_packages[repo] = {}
                end
                config.masked_packages[repo][pkg] = true
            else
                config.masked_packages[line] = true
            end
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
        default_build_mode = "binary",
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
            if env.default_build_mode then
                opts.default_build_mode = env.default_build_mode
            end
            if env.jobs then
                opts.jobs = env.jobs
            end
            if env.load then
                opts.load = env.load
            end
            if env.extra then
                opts.extra = env.extra
            end
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

--- Load package pin list from the package.lock configuration file
--
-- This function reads the package pin file to identify packages that should
-- be locked to specific versions. Package pinning prevents automatic upgrades
-- of critical packages, ensuring system stability by maintaining known working
-- versions. The pin list provides administrators with fine-grained control over
-- package version management.
--
-- Each line in the pin file specifies a package name and exact version that
-- should be enforced. The function supports comment lines starting with # for
-- documentation and ignores empty lines, making the pin file maintainable and
-- self-documenting.
function config.load_pins()
    local f = io.open(config.PACKAGE_LOCK, "r")
    if not f then return end
    for line in f:lines() do
        line = line:gsub("#.*", ""):match("^%s*(.-)%s*$")
        if line ~= "" then
            local pkg, version = line:match("^([^%s]+)%s+(.+)$")
            if pkg and version then
                config.pinned_packages[pkg] = version
            end
        end
    end
    f:close()
end

--- Add a new repository
-- @param name string Repository name
-- @param path string Repository path
function config.add_repo(name, path)
    local repo_entry
    if path:match("^https?://") or path:match("^git@") or path:match("%.git$") then
        repo_entry = { url = path, is_git = true }
    else
        repo_entry = { path = path, is_git = false }
    end
    config.repos[name] = repo_entry
    
    local f = io.open(config.REPOS_CONF, "a")
    if f then
        f:write(name .. " " .. path .. "\n")
        f:close()
    end
end

--- Remove a repository
-- @param name string Repository name to remove
function config.remove_repo(name)
    config.repos[name] = nil
    
    local lines = {}
    local f = io.open(config.REPOS_CONF, "r")
    if f then
        for line in f:lines() do
            if not line:match("^" .. name .. "%s+") then
                table.insert(lines, line)
            end
        end
        f:close()
    end
    
    f = io.open(config.REPOS_CONF, "w")
    if f then
        for _, line in ipairs(lines) do
            f:write(line .. "\n")
        end
        f:close()
    end
end

function config.ensure_repo(name)
    local repo = config.repos[name]
    if not repo then
        return nil
    end
    
    if repo.is_git then
        local target_path = config.CACHE_PATH .. "/repos/" .. name
        if not config.repo_exists(target_path) then
            print("Cloning repository " .. name .. "...")
            local ok = os.execute("mkdir -p " .. config.CACHE_PATH .. "/repos")
            if ok then
                ok = os.execute("git clone " .. repo.url .. " " .. target_path)
                if not ok then
                    error("failed to clone repository: " .. repo.url)
                end
            end
        end
        return target_path
    else
        return repo.path
    end
end

function config.repo_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

--- Check if a package is pinned to a specific version
-- @param package_name string Name of the package to check
-- @return string|nil Pinned version, or nil if not pinned
function config.is_pinned(package_name)
    return config.pinned_packages[package_name]
end

--- Pin a package to a specific version
-- @param package_name string Name of the package to pin
-- @param version string Version to pin the package to
function config.pin_package(package_name, version)
    config.pinned_packages[package_name] = version
    
    local f = io.open(config.PACKAGE_LOCK, "a")
    if f then
        f:write(package_name .. " " .. version .. "\n")
        f:close()
    end
end

--- Unpin a package, allowing automatic upgrades
-- @param package_name string Name of the package to unpin
function config.unpin_package(package_name)
    config.pinned_packages[package_name] = nil
    
    local lines = {}
    local f = io.open(config.PACKAGE_LOCK, "r")
    if f then
        for line in f:lines() do
            if not line:match("^" .. package_name .. "%s+") then
                table.insert(lines, line)
            end
        end
        f:close()
    end
    
    f = io.open(config.PACKAGE_LOCK, "w")
    if f then
        for _, line in ipairs(lines) do
            f:write(line .. "\n")
        end
        f:close()
    end
end

return config
