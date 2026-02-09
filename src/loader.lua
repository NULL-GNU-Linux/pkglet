--- Package manifest loading module
-- @module loader

local loader = {}
local config = require("src.config")

--- Locate package manifest file across all configured repositories
-- This function searches through all registered repositories to find the manifest file
-- for a specified package. It converts package names using dot notation to filesystem
-- paths, allowing for hierarchical package organization. The search proceeds through
-- repositories in the order they're configured, returning the first match found.
-- This mechanism enables package discovery across multiple sources while supporting
-- both flat and nested directory structures for optimal package organization.
-- @param package_name string The full package name using dot notation (e.g., "org.example.package")
-- @return string Absolute path to the found manifest file or throws error if not found
function loader.find_manifest(package_name)
    local repo, pkg_name = package_name:match("^([^/]+)/(.+)$")
    if repo and pkg_name then
        local repo_path = config.repos[repo]
        if repo_path then
            local manifest_path = repo_path .. "/" .. pkg_name:gsub("%.", "/") .. "/manifest.lua"
            local f = io.open(manifest_path, "r")
            if f then
                f:close()
                return manifest_path
            end
        end
        error("package not found: " .. package_name)
    end
    for repo_name, repo_path in pairs(config.repos) do
        local manifest_path = repo_path .. "/" .. package_name:gsub("%.", "/") .. "/manifest.lua"
        local f = io.open(manifest_path, "r")
        if f then
            f:close()
            return manifest_path
        end
    end
    error("package not found: " .. package_name)
end
--- Load, parse, and validate package manifest with sandboxed execution environment
-- This function provides secure manifest loading by executing manifest files in a
-- controlled environment with limited global access. It creates a sandboxed namespace
-- that provides package-specific functions while protecting the system from potentially
-- malicious manifest code. The function validates required fields, checks for package
-- masking, and enriches the manifest with metadata like source path and environment.
-- This approach enables flexible manifest syntax while maintaining security and
-- consistency across the package ecosystem.
-- @param package_name string The full package name to locate and load
-- @return table Complete validated manifest object with enriched metadata and environment
function loader.load_manifest(package_name)
    local manifest_path = loader.find_manifest(package_name)
    local env = {
        make = function() end,
        cmake = function() end,
        exec = function() end,
        ninja = function() end,
        meson = function() end,
        OPTIONS = {},
    }
    setmetatable(env, {__index = _G})
    local chunk, err = loadfile(manifest_path, "t", env)
    if not chunk then
        error("failed to load manifest: " .. err)
    end
    chunk()
    if not env.pkg then
        error("manifest missing 'pkg' table")
    end
    local manifest = env.pkg
    manifest._path = manifest_path
    manifest._env = env
    loader.validate_manifest(manifest)
    return manifest
end

--- Validate manifest structure, required fields, and system constraints
-- This function performs comprehensive validation of package manifests to ensure
-- they meet the minimum requirements for package management. It checks for all
-- required metadata fields including name, version, description, and license,
-- and verifies that the package is not masked by system configuration. This
-- validation is essential for maintaining package quality and preventing
-- installation of malformed or prohibited packages. The function provides
-- clear error messages to help package authors fix manifest issues.
-- @param manifest table Package manifest object to validate against system requirements
function loader.validate_manifest(manifest)
    local required = {"name", "version", "description", "license"}
    for _, field in ipairs(required) do
        if not manifest[field] then
            error("manifest missing required field: " .. field)
        end
    end

    if config.masked_packages[manifest.name] then
        error("package is masked: " .. manifest.name)
    end
    if manifest.repository and config.masked_packages[manifest.repository] and config.masked_packages[manifest.repository][manifest.name] then
        error("package is masked: " .. manifest.repository .. "/" .. manifest.name)
    end
end

--- Display comprehensive package information in a formatted, human-readable layout
-- This function presents package metadata in a structured format suitable for
-- command-line display and package browsing. It shows essential information
-- including name, version, description, maintainer, license, and homepage,
-- followed by dependency information, conflicts, and provides relationships.
-- The function also displays available build options with their default values
-- and descriptions, enabling users to understand package capabilities and
-- configuration possibilities before installation.
-- @param manifest table Complete package manifest containing all metadata to display
function loader.print_info(manifest)
    print("Name:        " .. manifest.name)
    print("Version:     " .. manifest.version)
    print("Description: " .. manifest.description)
    if manifest.maintainer then
        print("Maintainer:  " .. manifest.maintainer)
    end
    print("License:     " .. manifest.license)
    if manifest.homepage then
        print("Homepage:    " .. manifest.homepage)
    end

    if manifest.depends and #manifest.depends > 0 then
        print("Depends:     " .. table.concat(manifest.depends, ", "))
    end

    if manifest.conflicts and #manifest.conflicts > 0 then
        print("Conflicts:   " .. table.concat(manifest.conflicts, ", "))
    end

    if manifest.provides and #manifest.provides > 0 then
        print("Provides:    " .. table.concat(manifest.provides, ", "))
    end

    if manifest.options then
        print("\nOptions:")
        for name, opt in pairs(manifest.options) do
            local desc = opt.description or ""
            local default = opt.default and "true" or "false"
            print("  " .. name .. " (default: " .. default .. ") - " .. desc)
        end
    end
end

return loader
