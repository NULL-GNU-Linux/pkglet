--- Package installation module
-- @module installer

local installer = {}
local config = require("src.config")
local fetcher = require("src.fetcher")
local builder = require("src.builder")
local resolver = require("src.resolver")
local loader = require("src.loader")

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
    if os.getenv("PKGLET_DEBUG") == "1" then
        print("DEBUG: args =")
        for k, v in pairs(args) do
            print("  " .. k .. " = " .. tostring(v))
        end
    end

    if args.bootstrap_to then
        config.set_bootstrap_root(args.bootstrap_to)
        print("Bootstrap mode: installing to " .. config.ROOT)
    end

    local conflict = require("src.conflict")
    local conflicts = conflict.check_conflicts(manifest.name, manifest)

    if #conflicts > 0 then
        local can_resolve = conflict.resolve_conflicts(manifest.name, conflicts, args.force)
        if not can_resolve then
            error("installation aborted due to unresolvable conflicts")
        end
    end

    if args.options.hook then
        return installer.run_single_hook(manifest, args)
    end

    if resolver.is_installed(manifest.name) then
        print("Package already installed: " .. manifest.name)
        return
    end

    local packages_to_install

    if args.nodeps then
        packages_to_install = {}
        if not resolver.is_installed(manifest.name) then
            packages_to_install[manifest.name] = manifest.version
        end
    else
        packages_to_install = installer.resolve_dependencies(manifest, {})

        if args.options and args.options.with_optional then
            print("Installing optional dependencies...")
            local optional_packages = installer.resolve_optional_dependencies(manifest, {})
            for name, version in pairs(optional_packages) do
                if not packages_to_install[name] then
                    packages_to_install[name] = version
                end
            end
        end
    end

    if installer.count_keys(packages_to_install) > 0 then
        print("Packages to install:")
        for name, version in pairs(packages_to_install) do
            print("  \27[7m" .. name .. "\27[0m " .. version)
        end
        print("")
    else
        if args.nodeps then
            print("Package already installed.")
        else
            print("All dependencies already installed.")
        end
        print("")
        return
    end
    if not args.noask then
        io.write("Proceed with installation? \27[7m[Y/n]\27[0m ")
        local response = io.read()
        if response and response:lower():sub(1,1) == 'n' then
            print("Installation cancelled.")
            return
        end
    end

    local install_order = {}
    for name, version in pairs(packages_to_install) do
        table.insert(install_order, name)
    end

    for _, name in ipairs(install_order) do
        local pkg_manifest = loader.load_manifest(name)
        print("Installing " .. pkg_manifest.name .. " " .. pkg_manifest.version)
        local build_type = installer.determine_build_type(pkg_manifest, args.build_from)
        print("Build type: " .. build_type)
        local options = installer.merge_options(pkg_manifest, args.options)
        local build_dir = config.BUILD_PATH .. "/" .. pkg_manifest.name
        local temp_install_dir = config.TEMP_INSTALL_PATH .. "/" .. pkg_manifest.name
        os.execute("rm -rf " .. build_dir)
        os.execute("mkdir -p " .. build_dir)
        os.execute("rm -rf " .. temp_install_dir)
        os.execute("mkdir -p " .. temp_install_dir)
        local source_spec
        if build_type == "source" then
            source_spec = pkg_manifest.sources.source
        else
            source_spec = pkg_manifest.sources.binary
        end
        if source_spec then
            fetcher.fetch(source_spec, build_dir)
        end
        builder.build(pkg_manifest, build_dir, build_type, options)
        local files_list = installer.copy_from_temp(pkg_manifest)
        installer.record_installation(pkg_manifest, files_list)
        print("Successfully installed " .. pkg_manifest.name)
    end
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

function installer.record_installation(manifest, files_list)
    local db_file = config.DB_PATH .. "/" .. manifest.name:gsub("%.", "-")
    local f = io.open(db_file, "w")
    if f then
        f:write("name=" .. manifest.name .. "\n")
        f:write("version=" .. manifest.version .. "\n")
        f:write("installed=" .. os.time() .. "\n")
        f:write("manifest_path=" .. manifest._path .. "\n")
        if files_list then
            for _, file in ipairs(files_list) do
                f:write("file=" .. file .. "\n")
            end
        end
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
    
    local files_list = {}
    local handle = io.popen("cd " .. temp_path .. " && find . -type f -o -type l")
    if handle then
        for line in handle:lines() do
            table.insert(files_list, line)
        end
        handle:close()
    end
    return files_list
end

function installer.get_dependencies(manifest)
    local version_module = require("src.version")
    local deps = {}
    if manifest.depends then
        for _, dep in ipairs(manifest.depends) do
            if type(dep) == "string" then
                local parsed = version_module.parse_dependency(dep)
                deps[parsed.name] = parsed.constraint
            elseif type(dep) == "table" then
                deps[dep.name] = dep.constraint or "*"
            end
        end
    end
    if manifest.build_depends then
        for _, dep in ipairs(manifest.build_depends) do
            if type(dep) == "string" then
                local parsed = version_module.parse_dependency(dep)
                deps[parsed.name] = parsed.constraint
            elseif type(dep) == "table" then
                deps[dep.name] = (dep.constraint or "*") .. ":build"
            end
        end
    end
    if manifest.optional_depends then
        for _, dep in ipairs(manifest.optional_depends) do
            if type(dep) == "string" then
                local parsed = version_module.parse_dependency(dep)
                deps[parsed.name] = (parsed.constraint or "*") .. ":optional"
            elseif type(dep) == "table" then
                deps[dep.name] = ((dep.constraint or "*") .. ":optional")
            end
        end
    end
    return deps
end

function installer.resolve_dependencies(manifest, visited)
    local version_module = require("src.version")
    visited = visited or {}
    local packages_to_install = {}

    if visited[manifest.name] then
        return {}
    end
    visited[manifest.name] = true

    if not resolver.is_installed(manifest.name) then
        packages_to_install[manifest.name] = manifest.version
    end

    local deps = installer.get_dependencies(manifest)
    local conflict = require("src.conflict")
    local resolved_deps = conflict.resolve_virtual_dependencies(deps)

    for dep_name, dep_constraint in pairs(resolved_deps) do
        local is_build_dep = dep_constraint:match(":build$") ~= nil
        local is_optional_dep = dep_constraint:match(":optional$") ~= nil

        if is_build_dep then
            dep_constraint = dep_constraint:gsub(":build$", "")
        elseif is_optional_dep then
            dep_constraint = dep_constraint:gsub(":optional$", "")
        end

        if not resolver.is_installed(dep_name) and not visited[dep_name] then
            if is_optional_dep then
                print("Optional dependency " .. dep_name .. " not installed, skipping")
            else
                local available_versions = version_module.get_available_versions(dep_name)
                local selected_version = version_module.highest_satisfying(available_versions, dep_constraint)

                if not selected_version then
                    error("no satisfying version found for " .. dep_name .. " " .. dep_constraint)
                end

                local dep_manifest = loader.load_manifest(dep_name)
                dep_manifest.version = selected_version
                local dep_packages = installer.resolve_dependencies(dep_manifest, visited)
                for name, version in pairs(dep_packages) do
                    packages_to_install[name] = version
                end
                if not visited[dep_name] then
                    packages_to_install[dep_name] = selected_version
                end
            end
        elseif resolver.is_installed(dep_name) then
            local current_version = installer.get_installed_version(dep_name)
            if not version_module.satisfies(dep_constraint, current_version) then
                if is_optional_dep then
                    print("Warning: installed optional dependency " .. dep_name .. " (" .. current_version .. ") does not satisfy constraint " .. dep_constraint)
                else
                    error("installed version of " .. dep_name .. " (" .. current_version .. ") does not satisfy constraint " .. dep_constraint)
                end
            end
        end
    end

    return packages_to_install
end

function installer.count_keys(table)
    local count = 0
    for _ in pairs(table) do
        count = count + 1
    end
    return count
end

function installer.remove_files(manifest)
    print("Removing files...")
    local db_file = config.DB_PATH .. "/" .. manifest.name:gsub("%.", "-")
    local f = io.open(db_file, "r")
    local files = {}
    if f then
        for line in f:lines() do
            local key, value = line:match("^([^=]+)=(.+)$")
            if key == "file" then
                table.insert(files, value)
            end
        end
        f:close()
    end
    
    for _, file in ipairs(files) do
        local full_path = config.ROOT .. "/" .. file
        os.execute("rm -f " .. full_path)
    end
    
    local temp_path = config.TEMP_INSTALL_PATH .. "/" .. manifest.name
    os.execute("rm -rf " .. temp_path)
    
    if #files > 0 then
        print("Removed " .. #files .. " files")
    end
end

function installer.run_single_hook(manifest, args)
    if os.getenv("PKGLET_DEBUG") == "1" then
        print("options =")
        for k, v in pairs(args.options) do
            print("  " .. k .. " = " .. tostring(v))
        end
    end

    local build_type = installer.determine_build_type(manifest, args.build_from)
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

    local build_fn
    if build_type == "source" then
        build_fn = manifest.source()
    else
        build_fn = manifest.binary()
    end

    local hooks = {}

    local function hook(name)
        return function(fn)
            hooks[name] = fn
        end
    end

    build_fn(hook)

    local hook_name = args.options.hook
    if hook_name == "prepare" and hooks.prepare then
        print("Running prepare hook...")
        hooks.prepare()
    elseif hook_name == "build" and hooks.build then
        print("Running build hook...")
        hooks.build()
    elseif hook_name == "pre_install" and hooks.pre_install then
        print("Running pre_install hook...")
        hooks.pre_install()
    elseif hook_name == "install" and hooks.install then
        print("Running install hook...")
        hooks.install()
        local files_list = installer.copy_from_temp(manifest)
        installer.record_installation(manifest, files_list)
    elseif hook_name == "post_install" and hooks.post_install then
        local files_list = installer.copy_from_temp(manifest)
        installer.record_installation(manifest, files_list)
        print("Running post_install hook...")
        hooks.post_install()
    else
        print("Hook '" .. hook_name .. "' not found or not available")
        return
    end

    print("Hook '" .. tostring(hook_name) .. "' completed successfully")
end

--- Resolve optional dependencies (installable but not required)
-- @param manifest table Package manifest
-- @param visited table Tracking set to prevent cycles (internal use)
-- @return table Optional dependencies that could be installed
function installer.resolve_optional_dependencies(manifest, visited)
    local version_module = require("src.version")
    local loader = require("src.loader")
    visited = visited or {}
    local optional_packages = {}
    if visited[manifest.name] then
        return {}
    end
    visited[manifest.name] = true
    if manifest.optional_depends then
        for _, dep in ipairs(manifest.optional_depends) do
            local dep_name, dep_constraint
            if type(dep) == "string" then
                local parsed = version_module.parse_dependency(dep)
                dep_name = parsed.name
                dep_constraint = parsed.constraint
            elseif type(dep) == "table" then
                dep_name = dep.name
                dep_constraint = dep.constraint or "*"
            end
            if not resolver.is_installed(dep_name) and not visited[dep_name] then
                local available_versions = version_module.get_available_versions(dep_name)
                local selected_version = version_module.highest_satisfying(available_versions, dep_constraint)
                if selected_version then
                    local dep_manifest = loader.load_manifest(dep_name)
                    dep_manifest.version = selected_version
                    local dep_optional = installer.resolve_optional_dependencies(dep_manifest, visited)
                    for name, version in pairs(dep_optional) do
                        optional_packages[name] = version
                    end
                    if not visited[dep_name] then
                        optional_packages[dep_name] = selected_version
                    end
                end
            end
        end
    end
    return optional_packages
end

--- Get installed version of a package
-- @param package_name string Name of the package
-- @return string|nil Installed version, or nil if not installed
function installer.get_installed_version(package_name)
    local db_file = config.DB_PATH .. "/" .. package_name:gsub("%.", "-")
    local f = io.open(db_file, "r")
    if not f then return nil end
    local version = nil
    for line in f:lines() do
        local key, value = line:match("^([^=]+)=(.+)$")
        if key == "version" then
            version = value
            break
        end
    end
    f:close()
    return version
end

--- Upgrade a package to the latest available version
-- @param package_name string Name of the package to upgrade
-- @param args table Installation arguments
function installer.upgrade(package_name, args)
    local version_module = require("src.version")
    local loader = require("src.loader")
    local resolver = require("src.resolver")
    if not resolver.is_installed(package_name) then
        print("Package not installed: " .. package_name)
        return
    end
    local current_version = installer.get_installed_version(package_name)
    local latest_version = version_module.get_latest_version(package_name, current_version)
    if not latest_version then
        print("Package " .. package_name .. " is already up to date at version " .. current_version)
        return
    end
    print("Upgrading " .. package_name .. " from " .. current_version .. " to " .. latest_version)
    local manifest = loader.load_manifest(package_name)
    manifest.version = latest_version
    installer.uninstall(manifest)
    installer.install(manifest, args)
end

--- Downgrade a package to a specific version (any string allowed)
-- @param package_name string Name of the package to downgrade
-- @param target_version string Target version to downgrade to (can be any string: tag, commit, etc.)
-- @param args table Installation arguments
function installer.downgrade(package_name, target_version, args)
    local version_module = require("src.version")
    local loader = require("src.loader")
    local resolver = require("src.resolver")
    if not resolver.is_installed(package_name) then
        print("Package not installed: " .. package_name)
        return
    end
    local current_version = installer.get_installed_version(package_name)
    print("Downgrading " .. package_name .. " from " .. current_version .. " to " .. target_version)
    local manifest = loader.load_manifest(package_name)
    manifest.version = target_version
    installer.uninstall(manifest)
    installer.install(manifest, args)
end

return installer
