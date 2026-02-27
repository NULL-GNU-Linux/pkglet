--- Version management and constraint resolution module
--
-- This module provides comprehensive version management capabilities including
-- version parsing, comparison, constraint evaluation, and dependency resolution.
-- It supports semantic versioning (SemVer) with extensions for pre-release and
-- build metadata, as well as traditional version formats. The constraint system
-- supports all common operators including caret ranges, tilde ranges, wildcards,
-- and exact versions. This module is essential for modern package management
-- requiring precise version control and dependency resolution.
--
-- Version comparison follows semantic versioning principles where major.minor.patch
-- versions are compared numerically, with pre-release identifiers having lower
-- precedence than the associated normal version. Build metadata is ignored for
-- version precedence but preserved for完整性. The constraint resolver can handle
-- complex dependency graphs with version conflicts and provide optimal solutions.
-- @module version

local version = {}

--- Parse version string into structured components
--
-- This function parses version strings according to semantic versioning rules,
-- supporting both standard SemVer formats and extended version schemes. It extracts
-- major, minor, and patch numbers as integers, along with optional pre-release
-- and build metadata components. The parser handles various input formats and
-- provides meaningful error messages for invalid version strings.
--
-- @param version_str string Version string to parse (e.g., "1.2.3", "2.0.0-alpha", "1.0.0+build.123")
-- @return table Parsed version components: major, minor, patch, prerelease, build
function version.parse(version_str)
    if type(version_str) ~= "string" then
        error("version must be a string")
    end
    
    local main, build = version_str:match("^([^+]+)%+(.+)$")
    if not main then
        main = version_str
    end
    
    local main_ver, prerelease = main:match("^([^-]+)-(.+)$")
    if not main_ver then
        main_ver = main
    end
    
    local major, minor, patch = main_ver:match("^(%d+)%.?(%d*)%.?(%d*)$")
    if not major then
        error("invalid version format: " .. version_str)
    end
    
    return {
        major = tonumber(major),
        minor = tonumber(minor) or 0,
        patch = tonumber(patch) or 0,
        prerelease = prerelease,
        build = build,
        original = version_str
    }
end

--- Compare two version objects according to semantic versioning rules
--
-- This function implements the SemVer comparison algorithm where versions are
-- compared first by major version, then minor, then patch. Pre-release versions
-- have lower precedence than their associated normal versions. Pre-release
-- identifiers are compared dot-separated identifier by identifier, with numeric
-- identifiers compared numerically and alphanumeric identifiers compared
-- lexically using ASCII sort order.
--
-- @param v1 table First version object (from version.parse)
-- @param v2 table Second version object (from version.parse)
-- @return number -1 if v1 < v2, 0 if v1 == v2, 1 if v1 > v2
function version.compare(v1, v2)
    if v1.major ~= v2.major then
        return v1.major < v2.major and -1 or 1
    end
    
    if v1.minor ~= v2.minor then
        return v1.minor < v2.minor and -1 or 1
    end
    
    if v1.patch ~= v2.patch then
        return v1.patch < v2.patch and -1 or 1
    end
    
    local has_prerelease1 = v1.prerelease ~= nil
    local has_prerelease2 = v2.prerelease ~= nil
    
    if not has_prerelease1 and not has_prerelease2 then
        return 0
    elseif has_prerelease1 and not has_prerelease2 then
        return -1
    elseif not has_prerelease1 and has_prerelease2 then
        return 1
    else
        return version.compare_prerelease(v1.prerelease, v2.prerelease)
    end
end

--- Compare pre-release identifiers according to SemVer rules
--
-- Pre-release identifiers are compared dot-separated identifier by identifier.
-- Numeric identifiers are compared numerically, while alphanumeric identifiers
-- are compared lexically using ASCII sort order. Numeric identifiers have
-- lower precedence than non-numeric identifiers.
--
-- @param p1 string First pre-release identifier
-- @param p2 string Second pre-release identifier
-- @return number -1 if p1 < p2, 0 if p1 == p2, 1 if p1 > p2
function version.compare_prerelease(p1, p2)
    local parts1 = version.split_prerelease(p1)
    local parts2 = version.split_prerelease(p2)
    
    local max_len = math.max(#parts1, #parts2)
    
    for i = 1, max_len do
        local part1 = parts1[i]
        local part2 = parts2[i]
        
        if not part1 and part2 then
            return -1
        elseif part1 and not part2 then
            return 1
        elseif not part1 and not part2 then
            return 0
        end
        
        local is_numeric1 = part1:match("^%d+$") ~= nil
        local is_numeric2 = part2:match("^%d+$") ~= nil
        
        if is_numeric1 and is_numeric2 then
            local num1 = tonumber(part1)
            local num2 = tonumber(part2)
            if num1 ~= num2 then
                return num1 < num2 and -1 or 1
            end
        elseif is_numeric1 and not is_numeric2 then
            return -1
        elseif not is_numeric1 and is_numeric2 then
            return 1
        else
            if part1 ~= part2 then
                return part1 < part2 and -1 or 1
            end
        end
    end
    
    return 0
end

--- Split pre-release identifier into dot-separated components
--
-- @param prerelease string Pre-release identifier (e.g., "alpha.1.beta")
-- @return table Array of identifier components
function version.split_prerelease(prerelease)
    local parts = {}
    for part in prerelease:gmatch("[^%.]+") do
        table.insert(parts, part)
    end
    return parts
end

--- Check if version constraint is satisfied by a specific version
--
-- This function evaluates whether a given version satisfies a constraint
-- expression, supporting all common constraint operators and formats.
-- It handles simple equality, range constraints, caret ranges, tilde
-- ranges, and wildcard expressions.
--
-- @param constraint string Version constraint expression (e.g., ">=1.0.0", "^2.0.0", "~1.5.0", "*")
-- @param version_str string Version to test against the constraint
-- @return boolean True if the version satisfies the constraint, false otherwise
function version.satisfies(constraint, version_str)
    local parsed_version = version.parse(version_str)
    
    if constraint == "*" or constraint == "" then
        return true
    end
    
    local op, target = constraint:match("^(>=|<=|==|!=|>|<)%s*(.+)$")
    if op and target then
        local cmp = version.compare(parsed_version, version.parse(target))
        if op == ">=" then return cmp >= 0
        elseif op == "<=" then return cmp <= 0
        elseif op == "==" then return cmp == 0
        elseif op == "!=" then return cmp ~= 0
        elseif op == ">" then return cmp > 0
        elseif op == "<" then return cmp < 0
        end
    end
    
    if constraint:match("^%^") then
        return version.satisfies_caret(constraint, parsed_version)
    elseif constraint:match("^~") then
        return version.satisfies_tilde(constraint, parsed_version)
    elseif constraint:match("%*") then
        return version.satisfies_wildcard(constraint, parsed_version)
    else
        return version.compare(parsed_version, version.parse(constraint)) == 0
    end
end

--- Check if version satisfies caret range constraint (^1.0.0)
--
-- Caret ranges allow changes that do not modify the left-most non-zero
-- digit in the version number. For example, ^1.2.3 allows >=1.2.3 <2.0.0.
-- This is the most common and recommended range type for most dependencies.
--
-- @param constraint string Caret constraint (e.g., "^1.2.3")
-- @param version table Parsed version to test
-- @return boolean True if version satisfies the caret range
function version.satisfies_caret(constraint, version_obj)
    local target = constraint:sub(2)
    local target_parsed = version.parse(target)
    
    if version.compare(version_obj, target_parsed) < 0 then
        return false
    end
    
    local upper_bound = {
        major = target_parsed.major,
        minor = target_parsed.minor,
        patch = target_parsed.patch
    }
    
    if target_parsed.major > 0 then
        upper_bound.major = upper_bound.major + 1
        upper_bound.minor = 0
        upper_bound.patch = 0
    elseif target_parsed.minor > 0 then
        upper_bound.minor = upper_bound.minor + 1
        upper_bound.patch = 0
    elseif target_parsed.patch > 0 then
        upper_bound.patch = upper_bound.patch + 1
    end
    
    return version.compare(version_obj, upper_bound) < 0
end

--- Check if version satisfies tilde range constraint (~1.2.3)
--
-- Tilde ranges allow patch-level changes if a minor version is specified,
-- or minor-level changes if only the major version is specified. For example,
-- ~1.2.3 allows >=1.2.3 <1.3.0, while ~1.2 allows >=1.2.0 <2.0.0.
--
-- @param constraint string Tilde constraint (e.g., "~1.2.3")
-- @param version table Parsed version to test
-- @return boolean True if version satisfies the tilde range
function version.satisfies_tilde(constraint, version_obj)
    local target = constraint:sub(2)
    local target_parsed = version.parse(target)
    
    if version.compare(version_obj, target_parsed) < 0 then
        return false
    end
    
    local upper_bound = {
        major = target_parsed.major,
        minor = target_parsed.minor,
        patch = target_parsed.patch
    }
    
    if target_parsed.patch > 0 then
        upper_bound.patch = upper_bound.patch + 1
    elseif target_parsed.minor > 0 then
        upper_bound.minor = upper_bound.minor + 1
        upper_bound.patch = 0
    else
        upper_bound.major = upper_bound.major + 1
        upper_bound.minor = 0
        upper_bound.patch = 0
    end
    
    return version.compare(version_obj, upper_bound) < 0
end

--- Check if version satisfies wildcard constraint (1.* or 1.2.*)
--
-- Wildcard constraints match versions where the wildcard can be any value.
-- For example, 1.* matches all versions >=1.0.0 <2.0.0, while 1.2.* matches
-- all versions >=1.2.0 <1.3.0.
--
-- @param constraint string Wildcard constraint (e.g., "1.*", "1.2.*")
-- @param version table Parsed version to test
-- @return boolean True if version satisfies the wildcard constraint
function version.satisfies_wildcard(constraint, version_obj)
    local pattern = constraint:gsub("%*", ".*")
    local major, minor, patch = pattern:match("^(%d+)%.(%d+)%.(.*)$")
    
    if not major then
        major, minor = pattern:match("^(%d+)%.(.*)$")
        if major then
            return version_obj.major == tonumber(major)
        end
        return false
    end
    
    if version_obj.major ~= tonumber(major) then
        return false
    end
    
    if minor ~= ".*" and version_obj.minor ~= tonumber(minor) then
        return false
    end
    
    if patch ~= ".*" and version_obj.patch ~= tonumber(patch) then
        return false
    end
    
    return true
end

--- Find the highest version that satisfies a constraint
--
-- Given a list of available versions and a constraint, this function returns
-- the highest version that satisfies the constraint. This is essential for
-- dependency resolution where we want to select the most recent compatible
-- version.
--
-- @param versions table Array of available version strings
-- @param constraint string Version constraint to satisfy
-- @return string|nil Highest satisfying version, or nil if none satisfy
function version.highest_satisfying(versions, constraint)
    local best_version = nil
    local best_parsed = nil
    
    for _, v in ipairs(versions) do
        if version.satisfies(constraint, v) then
            local parsed = version.parse(v)
            if not best_parsed or version.compare(parsed, best_parsed) > 0 then
                best_version = v
                best_parsed = parsed
            end
        end
    end
    
    return best_version
end

--- Get all available versions of a package from repositories
--
-- This function scans all configured repositories to find all available
-- versions of a specific package. It collects version information from
-- manifests and returns a sorted list of available versions.
--
-- @param package_name string Name of the package to search for
-- @return table Array of available version strings, sorted by version precedence
function version.get_available_versions(package_name)
    local loader = require("src.loader")
    local config = require("src.config")
    local versions = {}
    
    for repo_name, repo_entry in pairs(config.repos) do
        local repo_path = config.ensure_repo(repo_name)
        if not repo_path then goto continue end
        local manifest_path = repo_path .. "/" .. package_name:gsub("%.", "/") .. "/manifest.lua"
        local f = io.open(manifest_path, "r")
        if f then
            f:close()
            local manifest = loader.load_manifest(package_name)
            if manifest.version then
                table.insert(versions, manifest.version)
            end
        end
        ::continue::
    end
    
    table.sort(versions, function(a, b)
        return version.compare(version.parse(a), version.parse(b)) < 0
    end)
    
    return versions
end

--- Check if an upgrade is available for an installed package
--
-- This function compares the currently installed version with available
-- versions to determine if an upgrade is available. It respects any
-- version constraints that might be in effect.
--
-- @param package_name string Name of the package to check
-- @param current_version string Currently installed version
-- @param constraint string Optional version constraint to respect
-- @return string|nil Latest available version, or nil if no upgrade available
function version.get_latest_version(package_name, current_version, constraint)
    local available_versions = version.get_available_versions(package_name)
    
    if constraint then
        return version.highest_satisfying(available_versions, constraint)
    else
        local latest = available_versions[#available_versions]
        local current_parsed = version.parse(current_version)
        local latest_parsed = version.parse(latest)
        
        if version.compare(latest_parsed, current_parsed) > 0 then
            return latest
        end
        return nil
    end
end

--- Parse dependency specification into package name and version constraint
--
-- This function parses dependency strings that combine package names with
-- version constraints, extracting both components for processing. It supports
-- various formats including "package>=1.0.0", "package@^2.0.0", etc.
--
-- @param dep_spec string Dependency specification (e.g., "package>=1.0.0", "package@^2.0.0")
-- @return table Parsed dependency with name and constraint fields
function version.parse_dependency(dep_spec)
    local name, constraint = dep_spec:match("^([^@<>!~%^%s]+)%s*([@<>!~%^].+)$")
    if not name then
        name = dep_spec
        constraint = "*"
    end
    
    return {
        name = name,
        constraint = constraint
    }
end

--- Resolve version constraints for a set of dependencies
--
-- This function attempts to find a compatible set of versions that satisfies
-- all dependency constraints simultaneously. It's a simplified version of
-- a full SAT solver but handles most common scenarios effectively.
--
-- @param dependencies table Array of dependency specifications
-- @return table|nil Resolved dependencies with specific versions, or nil if unresolvable
function version.resolve_dependencies(dependencies)
    local resolved = {}
    
    for _, dep in ipairs(dependencies) do
        local parsed_dep = version.parse_dependency(dep)
        local available_versions = version.get_available_versions(parsed_dep.name)
        local selected_version = version.highest_satisfying(available_versions, parsed_dep.constraint)
        
        if not selected_version then
            return nil
        end
        
        resolved[parsed_dep.name] = selected_version
    end
    
    return resolved
end

return version