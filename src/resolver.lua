local resolver = {}
local loader = require("src.loader")
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

function resolver.is_installed(package_name)
    local config = require("src.config")
    local db_file = config.DB_PATH .. "/" .. package_name:gsub("%.", "-")
    local f = io.open(db_file, "r")
    if f then
        f:close()
        return true
    end
    return false
end

function resolver.is_provided(virtual_name)
    local conflict = require("src.conflict")
    local providers = conflict.get_providers(virtual_name)

    for _, provider in ipairs(providers) do
        if resolver.is_installed(provider) then
            return true
        end
    end

    return false
end

function resolver.get_provider(virtual_name)
    local conflict = require("src.conflict")
    local providers = conflict.get_providers(virtual_name)

    for _, provider in ipairs(providers) do
        if resolver.is_installed(provider) then
            return provider
        end
    end

    return nil
end

function resolver.check_conflicts(manifest)
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
