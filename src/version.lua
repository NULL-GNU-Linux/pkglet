local version = {}
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

function version.split_prerelease(prerelease)
    local parts = {}
    for part in prerelease:gmatch("[^%.]+") do
        table.insert(parts, part)
    end
    return parts
end

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
