--- Dependency resolution module
-- @module resolver

local resolver = {}
local loader = require("src.loader")

--- Recursively resolve package dependencies with cycle detection and install order calculation
-- This function implements sophisticated dependency resolution that handles complex
-- dependency graphs while preventing infinite loops through cycle detection. It
-- traverses the dependency tree depth-first, tracking visited packages to avoid
-- duplication and circular dependencies. The function returns dependencies in the
-- correct order for installation, ensuring that all prerequisites are installed
-- before the packages that depend on them. This is critical for maintaining system
-- consistency and enabling complex multi-package installations.
-- @param manifest table Package manifest whose dependencies need to be resolved
-- @param resolved table Accumulator for resolved dependencies in install order (optional, used internally for recursion)
-- @param seen table Tracking set to detect cycles and prevent duplicate processing (optional, used internally for recursion)
-- @return table Ordered list of package names representing dependencies in correct installation sequence
function resolver.resolve_dependencies(manifest, resolved, seen)
    resolved = resolved or {}
    seen = seen or {}
    if seen[manifest.name] then
        return resolved
    end
    seen[manifest.name] = true
    if not manifest.depends then
        return resolved
    end
    for _, dep_name in ipairs(manifest.depends) do
        if not resolver.is_installed(dep_name) then
            local dep_manifest = loader.load_manifest(dep_name)
            resolver.resolve_dependencies(dep_manifest, resolved, seen)
            table.insert(resolved, dep_name)
        end
    end
    return resolved
end

--- Check package installation status by querying the package database
-- This function provides a reliable method to determine whether a package is currently
-- installed on the system by checking for the existence of its database record.
-- It uses the same naming convention as the installation system, converting package
-- names with dots to hyphens for filesystem compatibility. This function is
-- essential for dependency resolution, conflict detection, and system management
-- operations that need to differentiate between installed and available packages.
-- @param package_name string The full package name to check using dot notation
-- @return boolean True if the package is currently installed, false otherwise
function resolver.is_installed(package_name)
    local config = require("config")
    local db_file = config.DB_PATH .. "/" .. package_name:gsub("%.", "-")
    local f = io.open(db_file, "r")
    if f then
        f:close()
        return true
    end
    return false
end

--- Validate that no conflicting packages are currently installed
-- This function performs conflict resolution by checking the current installation
-- database against the package's declared conflicts list. It prevents installation
-- of packages that would interfere with each other, maintaining system stability
-- and preventing unexpected behavior. Conflicts are common when packages provide
-- alternative implementations of the same functionality or when they modify shared
-- system resources. This check is performed before installation to ensure that
-- the system remains in a consistent state after package operations.
-- @param manifest table Package manifest containing the conflicts list to validate against current installations
    if not manifest.conflicts then
        return
    end
    for _, conflict in ipairs(manifest.conflicts) do
        if resolver.is_installed(conflict) then
            error("package conflicts with installed package: " .. conflict)
        end
    end
end

return resolver
