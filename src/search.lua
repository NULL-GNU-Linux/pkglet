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
    for repo_name, repo_path in pairs(config.repos) do
        search.scan_repo(repo_path, pattern, results)
    end
    if #results == 0 then
        print("No packages found matching: " .. pattern)
        return
    end
    print("Found " .. #results .. " package(s):")
    for _, pkg in ipairs(results) do
        print("  " .. pkg.name .. " - " .. pkg.description)
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

function search.scan_repo(repo_path, pattern, results)
    local cmd = "find " .. repo_path .. " -name manifest.lua"
    local handle = io.popen(cmd)
    if not handle then return end
    for line in handle:lines() do
        local manifest_path = line:match("^%s*(.-)%s*$")
        if manifest_path and manifest_path ~= "" then
            local ok, manifest = pcall(function()
                local env = {}
                setmetatable(env, {__index = _G})
                local chunk = loadfile(manifest_path, "t", env)
                if chunk then
                    chunk()
                    return env.pkg
                end
            end)
            if ok and manifest and manifest.name then
                if pattern == "" or
                   manifest.name:find(pattern, 1, true) or
                   (manifest.description and manifest.description:lower():find(pattern:lower(), 1, true)) then
                    table.insert(results, manifest)
                end
            end
        end
    end
    handle:close()
end

return search
