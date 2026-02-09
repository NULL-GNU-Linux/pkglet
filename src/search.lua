--- Package search module
-- @module search

local search = {}
local config = require("src.config")
local loader = require("src.loader")

--- Search for packages across all repositories using pattern matching
-- This function provides comprehensive package search capabilities by scanning
-- all configured repositories and finding packages that match the specified
-- pattern. The search matches against both package names and descriptions,
-- providing flexible discovery options for users. It aggregates results from
-- multiple sources and presents them in a consistent format, making it easy
-- to find relevant packages regardless of which repository contains them.
-- The function handles empty patterns by returning all available packages.
-- @param pattern string Search pattern to match against package names and descriptions,
--                      can be partial matching and is case-insensitive for descriptions
function search.query(pattern)
    local results = {}
    if not config.repos or next(config.repos) == nil then
        print("\27[1;31merror\27[0m: no repositories configured.")
        return
    end
    for repo_name, repo_path in pairs(config.repos) do
        search.scan_repo(repo_name, repo_path, pattern, results)
    end
    if #results == 0 then
        print("\27[1;31merror\27[0m: target not found: " .. pattern)
        return
    end
    for _, pkg in ipairs(results) do
        local repo = pkg.repository or "local"
        local masked = ""
        if config.masked_packages[pkg.name] then
            masked = "\27[1;31m[ Masked ]\27[0m"
        elseif config.masked_packages[repo] and config.masked_packages[repo][pkg.name] then
            masked = "\27[1;31m[ Masked ]\27[0m"
        end
        local latest = pkg.version or "unknown"
        local installed = pkg.installed_version or "\27[31m[ Not Installed ]\27[0m"
        local homepage = pkg.homepage or "No homepage"
        local description = pkg.description or "No description"
        local license = pkg.license or "unknown"
        print("\27[1;32m*\27[0m  " .. repo .. "/" .. pkg.name .. " " .. masked)
        print("      Latest version available: " .. latest)
        print("      Latest version installed: " .. installed)
        print("      Homepage:      " .. homepage)
        print("      Description:   " .. description)
        print("      License:       " .. license)
        print()
    end
end

--- Scan individual repository for packages matching the search pattern
-- This function performs detailed scanning of a single repository, examining
-- all manifest files and checking them against the search pattern. It uses
-- safe manifest loading with error handling to prevent malformed manifests
-- from interrupting the search process. The matching is performed on both
-- package names (exact substring matching) and descriptions (case-insensitive),
-- providing comprehensive search coverage. This modular approach allows
-- efficient parallel processing of multiple repositories.
-- @param repo_path string Filesystem path to the repository directory to scan
-- @param pattern string Search pattern for matching packages
-- @param results table Accumulator table where matching packages will be stored

function search.scan_repo(repo_name, repo_path, pattern, results)
    pattern = pattern or ""
    if not repo_path or repo_path == "" then
        return
    end
    local cmd = "find " .. repo_path .. " -name manifest.lua"
    local handle = io.popen(cmd)
    if not handle then return end
    for line in handle:lines() do
        local manifest_path = line:match("^%s*(.-)%s*$")
        if manifest_path and manifest_path ~= "" then
            local ok, manifest = pcall(function()
                local env = {}
                setmetatable(env, {__index = _G})
                local chunk, err = loadfile(manifest_path, "t", env)
                if not chunk then
                    return nil
                end
                chunk()
                return env.pkg
            end)
            if ok and manifest then
                if manifest.name then
                    local name_match = manifest.name:find(pattern, 1, true)
                    local desc_match = nil
                    if manifest.description then
                        desc_match = manifest.description:lower():find(pattern:lower(), 1, true)
                    end
                    if pattern == "" or name_match or desc_match then
                        manifest.repository = repo_name
                        table.insert(results, manifest)
                    end
                elseif manifest.name then
                    if pattern == "" or manifest.name:find(pattern, 1, true) then
                        manifest.repository = repo_name
                        table.insert(results, manifest)
                    end
                end
            end
        end
    end
    handle:close()
end

return search
