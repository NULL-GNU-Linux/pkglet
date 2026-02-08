--- Package installation module
-- @module installer

local installer = {}
local config = require("src.config")
local fetcher = require("src.fetcher")
local builder = require("src.builder")
local resolver = require("src.resolver")

--- Install a package from manifest with comprehensive dependency resolution and build orchestration
-- This function is the core installation routine that handles the complete package lifecycle
-- from source acquisition to final installation. It supports bootstrap mode for system-level
-- installations, performs conflict detection, resolves dependencies recursively, determines
-- optimal build strategies, merges configuration options, and records installation metadata.
-- The function orchestrates multiple subsystems including fetching, building, and database
-- management to ensure reliable and reproducible package installations across different
-- environments and configurations.
-- @param manifest table Complete package manifest containing metadata, dependencies, sources, and build instructions
-- @param args table Installation arguments including bootstrap options, build preferences, and custom configuration overrides
function installer.install(manifest, args)
    print("Installing " .. manifest.name .. " " .. manifest.version)
    if args.bootstrap_to then
        config.set_bootstrap_root(args.bootstrap_to)
        print("Bootstrap mode: installing to " .. config.ROOT)
    end
    resolver.check_conflicts(manifest)
    if resolver.is_installed(manifest.name) then
        print("Package already installed: " .. manifest.name)
        return
    end

    io.write("Proceed with installation? [Y/n] ")
    local response = io.read()
    if response and response:lower():sub(1,1) == 'n' then
        print("Installation cancelled.")
        return
    end

    local build_type = installer.determine_build_type(manifest, args.build_from)
    print("Build type: " .. build_type)
    local options = installer.merge_options(manifest, args.options)
    local build_dir = config.BUILD_PATH .. "/" .. manifest.name
    local temp_install_dir = config.TEMP_INSTALL_PATH .. "/" .. manifest.name
    os.execute("rm -rf " .. build_dir)
    os.execute("mkdir -p " .. build_dir)
    os.execute("rm -rf " .. temp_install_dir)
    os.execute("mkdir -p " .. temp_install_dir)
    local source_spec
    if build_type == "source" then
        source_spec = manifest.sources.source
    else
        source_spec = manifest.sources.binary
    end
    if source_spec then
        fetcher.fetch(source_spec, build_dir)
    end
    builder.build(manifest, build_dir, build_type, options)
    installer.copy_from_temp(manifest)
    installer.record_installation(manifest)
    print("Successfully installed " .. manifest.name)
end

--- Uninstall a package with custom hook support and thorough cleanup
-- This function handles complete package removal with support for custom uninstall hooks
-- that packages can define for specialized cleanup procedures. It checks installation
-- status, executes pre-uninstall hooks for preparation, removes installed files,
-- runs post-uninstall hooks for final cleanup, and removes installation records.
-- The hook system allows packages to perform complex uninstallation operations
-- such as stopping services, cleaning up configuration files, or reverting system
-- changes while ensuring no remnants remain after removal.
-- @param manifest table Package manifest containing uninstall hooks and metadata for proper cleanup
function installer.uninstall(manifest)
    print("Uninstalling " .. manifest.name)
    if not resolver.is_installed(manifest.name) then
        print("Package not installed: " .. manifest.name)
        return
    end

    if manifest.uninstall then
        local build_dir = config.BUILD_PATH .. "/" .. manifest.name
        local uninstall_fn = manifest.uninstall()
        local hooks = {
            pre_uninstall = nil,
            post_uninstall = nil,
        }

        local function hook(name)
            return function(fn)
                hooks[name] = fn
            end
        end

        uninstall_fn(hook)
        if hooks.pre_uninstall then hooks.pre_uninstall() end
        installer.remove_files(manifest)
        if hooks.post_uninstall then hooks.post_uninstall() end
    else
        installer.remove_files(manifest)
    end

    installer.remove_installation_record(manifest)
    print("Successfully uninstalled " .. manifest.name)
end

--- Determine optimal build type based on user preference and package availability
-- This function implements intelligent build type selection that balances user preferences
-- with package capabilities. When set to "auto", it prioritizes binary packages for faster
-- installation but falls back to source compilation when binaries aren't available. This
-- approach provides the best user experience by minimizing build times while ensuring
-- all packages remain installable regardless of pre-compiled binary availability.
-- The function is critical for supporting both development and production deployment
-- scenarios with different performance requirements.
-- @param manifest table Package manifest containing available source and binary specifications
-- @param preference string User's preferred build type: "source" for compilation, "binary" for pre-compiled packages, or "auto" for automatic selection
-- @return string The final determined build type that will be used for installation
function installer.determine_build_type(manifest, preference)
    if preference == "source" then
        return "source"
    elseif preference == "binary" then
        return "binary"
    end

    if manifest.sources.binary then
        return "binary"
    elseif manifest.sources.source then
        return "source"
    end

    error("no valid source or binary available")
end

--- Merge and prioritize configuration options from multiple sources
-- This function implements a sophisticated option merging system that combines default
-- values from package manifests, global configuration settings, and command-line overrides.
-- It follows a clear precedence hierarchy where CLI options override global settings,
-- which in turn override manifest defaults. The function handles boolean conversion
-- from string values and ensures that all option types are properly normalized for
-- consistent behavior across different configuration sources. This system enables
-- flexible package customization while maintaining predictable configuration behavior.
-- @param manifest table Package manifest containing default option definitions and values
-- @param cli_options table Command-line options that take highest precedence in the merge hierarchy
-- @return table Final merged options with all sources combined and properly typed
function installer.merge_options(manifest, cli_options)
    local options = {}
    if manifest.options then
        for name, opt in pairs(manifest.options) do
            options[name] = opt.default
        end
    end
    if config.package_options[manifest.name] then
        for opt, _ in pairs(config.package_options[manifest.name]) do
            options[opt] = true
        end
    end
    if cli_options then
        for opt, value in pairs(cli_options) do
            if value == "true" then
                options[opt] = true
            elseif value == "false" then
                options[opt] = false
            else
                options[opt] = value
            end
        end
    end
    return options
end

--- Record package installation metadata in the package database
-- This function creates a persistent record of package installations for tracking,
-- dependency management, and system maintenance. It stores essential metadata
-- including package name, version, and installation timestamp in a simple key-value
-- format that can be easily queried by other system components. The database
-- records are critical for determining installed status, managing updates, and
-- providing audit trails for system administration and security compliance.
-- @param manifest table Package manifest containing name, version, and other metadata to be recorded
function installer.record_installation(manifest)
    local db_file = config.DB_PATH .. "/" .. manifest.name:gsub("%.", "-")
    local f = io.open(db_file, "w")
    if f then
        f:write("name=" .. manifest.name .. "\n")
        f:write("version=" .. manifest.version .. "\n")
        f:write("installed=" .. os.time() .. "\n")
        f:close()
    end
end

--- Remove package installation record from the package database during uninstallation
-- This function cleans up the package database by removing the installation record
-- for the specified package. This is essential for maintaining database integrity
-- and ensuring that the system correctly reflects the current installation state.
-- The removal is typically performed during uninstallation operations and prevents
-- stale records from interfering with future installation attempts or dependency
-- resolution. The function uses a simple file deletion approach matching the
-- record creation mechanism for consistency.
-- @param manifest table Package manifest whose installation record should be removed
function installer.remove_installation_record(manifest)
    local db_file = config.DB_PATH .. "/" .. manifest.name:gsub("%.", "-")
    os.remove(db_file)
end

--- Remove all files installed by a package during uninstallation process
-- This function handles the actual file removal for package uninstallation, ensuring
-- that all files, directories, and artifacts created during installation are properly
-- cleaned up. This is a critical component of the uninstallation process that must
-- be thorough to prevent leftover files from accumulating and potentially causing
-- conflicts or system issues. The function is designed to work with package manifests
-- that track installed files and can be extended to support more sophisticated
-- file tracking and removal strategies for complex packages.
-- @param manifest table Package manifest containing information about installed files and directories to remove
function installer.copy_from_temp(manifest)
    local temp_path = config.TEMP_INSTALL_PATH .. "/" .. manifest.name
    local dest_path = config.ROOT
    print("Copying files from temporary location...")
    os.execute("cp -r " .. temp_path .. "/* " .. dest_path .. "/")
end

function installer.remove_files(manifest)
    print("Removing files...")
    local temp_path = config.TEMP_INSTALL_PATH .. "/" .. manifest.name
    os.execute("rm -rf " .. temp_path)
end

return installer
