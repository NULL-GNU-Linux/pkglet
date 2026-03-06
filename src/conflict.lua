local conflict = {}
local resolver = require("src.resolver")
local loader = require("src.loader")
local installer = require("src.installer")
local config = require("src.config")
function conflict.get_providers(virtual_name)
    local providers = {}
    for repo_name, repo_entry in pairs(config.repos) do
        local repo_path = config.ensure_repo(repo_name)
        if not repo_path then goto continue end
        local cmd = "find " .. repo_path .. " -name manifest.lua"
        local handle = io.popen(cmd)
        if handle then
            for line in handle:lines() do
                local manifest_path = line:match("^%s*(.-)%s*$")
                if manifest_path and manifest_path ~= "" then
                    local ok, manifest = pcall(function()
                        local env = { ARCH = "x86_64" }
                        setmetatable(env, {__index = _G})
                        local chunk, err = loadfile(manifest_path, "t", env)
                        if not chunk then return nil end
                        chunk()
                        return env.pkg
                    end)

                    if ok and manifest and manifest.provides then
                        for _, provides in ipairs(manifest.provides) do
                            if provides == virtual_name then
                                table.insert(providers, manifest.name)
                                break
                            end
                        end
                    end
                end
            end
            handle:close()
        end
        ::continue::
    end

    return providers
end

function conflict.check_conflicts(package_name, manifest)
    local conflicts = {}

    if manifest.conflicts then
        for _, conflict_pkg in ipairs(manifest.conflicts) do
            if resolver.is_installed(conflict_pkg) then
                table.insert(conflicts, {
                    package = conflict_pkg,
                    reason = "explicit conflict in manifest"
                })
            end
        end
    end

    if manifest.replaces then
        for _, replaces_pkg in ipairs(manifest.replaces) do
            if resolver.is_installed(replaces_pkg) then
                table.insert(conflicts, {
                    package = replaces_pkg,
                    reason = "package replaces this package",
                    action = "replace"
                })
            end
        end
    end

    local file_conflicts = conflict.check_file_conflicts(package_name, manifest)
    for _, file_conflict in ipairs(file_conflicts) do
        table.insert(conflicts, {
            package = file_conflict.package,
            reason = "file conflict: " .. file_conflict.file,
            action = "file_conflict"
        })
    end

    return conflicts
end

function conflict.check_file_conflicts(package_name, manifest)
    local conflicts = {}

    if not manifest.files then
        return conflicts
    end

    for _, installed_pkg_name in ipairs(conflict.get_installed_packages()) do
        local installed_manifest = conflict.get_installed_manifest(installed_pkg_name)
        if installed_manifest and installed_manifest.files then
            for _, file in ipairs(manifest.files) do
                for _, installed_file in ipairs(installed_manifest.files) do
                    if file == installed_file then
                        table.insert(conflicts, {
                            package = installed_pkg_name,
                            file = file
                        })
                        break
                    end
                end
            end
        end
    end

    return conflicts
end

function conflict.get_installed_packages()
    local packages = {}
    local cmd = "find " .. config.DB_PATH .. " -name '*-name' 2>/dev/null"
    local handle = io.popen(cmd)
    if handle then
        for line in handle:lines() do
            local db_file = line:match("^%s*(.-)%s*$")
            if db_file then
                local package_name = db_file:match("([^/]+)$")
                if package_name then
                    package_name = package_name:gsub("-name$", "")
                    package_name = package_name:gsub("-", ".")
                    table.insert(packages, package_name)
                end
            end
        end
        handle:close()
    end
    return packages
end

function conflict.get_installed_manifest(package_name)
    local db_file = config.DB_PATH .. "/" .. package_name:gsub("%.", "-") .. "/manifest"
    local f = io.open(db_file, "r")
    if not f then return nil end

    local content = f:read("*a")
    f:close()

    local env = {}
    setmetatable(env, {__index = _G})
    local chunk, err = load(content, db_file, "t", env)
    if not chunk then return nil end

    chunk()
    return env.pkg
end

function conflict.resolve_conflicts(package_name, conflicts, force)
    if #conflicts == 0 then
        return true
    end

    print("Package " .. package_name .. " conflicts with:")
    for _, conflict in ipairs(conflicts) do
        local action = conflict.action or "conflict"
        local icon = action == "replace" and "→" or "✗"
        print("  " .. icon .. " " .. conflict.package .. " (" .. conflict.reason .. ")")
    end

    if not force then
        print("\nResolutions:")
        print("  1. Remove conflicting packages and continue")
        print("  2. Abort installation")

        io.write("Choose resolution [1/2]: ")
        local choice = io.read()

        if choice == "1" then
            return conflict.remove_conflicts(package_name, conflicts)
        else
            return false
        end
    else
        return conflict.remove_conflicts(package_name, conflicts)
    end
end

function conflict.remove_conflicts(package_name, conflicts)
    for _, conflict in ipairs(conflicts) do
        if conflict.action ~= "file_conflict" then
            print("Removing conflicting package: " .. conflict.package)
            local conflict_manifest = loader.load_manifest(conflict.package)
            installer.uninstall(conflict_manifest)
        end
    end
    return true
end

function conflict.select_provider(virtual_name, constraint)
    local providers = conflict.get_providers(virtual_name)
    local version_module = require("src.version")

    local best_provider = nil
    local best_version = nil

    for _, provider in ipairs(providers) do
        local manifest = loader.load_manifest(provider)
        if resolver.is_installed(provider) then
            local current_version = installer.get_installed_version(provider)
            if not constraint or version_module.satisfies(constraint, current_version) then
                return provider
            end
        else
            if not constraint or version_module.satisfies(constraint, manifest.version) then
                local parsed_version = version_module.parse(manifest.version)
                if not best_version or version_module.compare(parsed_version, best_version) > 0 then
                    best_provider = provider
                    best_version = parsed_version
                end
            end
        end
    end

    return best_provider
end

function conflict.who_provides(file_path)
    local providers = {}

    for _, package_name in ipairs(conflict.get_installed_packages()) do
        local manifest = conflict.get_installed_manifest(package_name)
        if manifest and manifest.files then
            for _, file in ipairs(manifest.files) do
                if file == file_path then
                    table.insert(providers, package_name)
                    break
                end
            end
        end
    end

    return providers
end

function conflict.resolve_virtual_dependencies(dependencies)
    local resolved = {}

    for dep_name, dep_constraint in pairs(dependencies) do
        local is_virtual = false

        for repo_name, repo_entry in pairs(config.repos) do
            local repo_path = config.ensure_repo(repo_name)
            if not repo_path then goto continue2 end
            local cmd = "find " .. repo_path .. " -name manifest.lua"
            local handle = io.popen(cmd)
            if handle then
                for line in handle:lines() do
                    local manifest_path = line:match("^%s*(.-)%s*$")
                    if manifest_path and manifest_path ~= "" then
                        local ok, manifest = pcall(function()
                            local env = {}
                            setmetatable(env, {__index = _G})
                            local chunk, err = loadfile(manifest_path, "t", env)
                            if not chunk then return nil end
                            chunk()
                            return env.pkg
                        end)

                        if ok and manifest and manifest.name == dep_name then
                            is_virtual = true
                            break
                        end
                    end
                end
                handle:close()
            end
            ::continue2::
        end
        if not is_virtual then
            local provider = conflict.select_provider(dep_name, dep_constraint)
            if provider then
                resolved[provider] = dep_constraint
            else
                resolved[dep_name] = dep_constraint
            end
        else
            resolved[dep_name] = dep_constraint
        end
    end

    return resolved
end

return conflict
