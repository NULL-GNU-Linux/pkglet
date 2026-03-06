local search = {}
local config = require("src.config")
local loader = require("src.loader")
function search.query(pattern)
	local results = {}
	if not config.repos or next(config.repos) == nil then
		print("\27[1;31merror\27[0m: no repositories configured.")
		return
	end
	for repo_name, repo_entry in pairs(config.repos) do
		local repo_path = config.ensure_repo(repo_name)
		if repo_path then
			search.scan_repo(repo_name, repo_path, pattern, results)
		end
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

		local resolver = require("src.resolver")
		local installed = "unknown"
		if resolver.is_installed(pkg.name) then
			local installed_version = search.get_installed_version(pkg.name)
			installed = installed_version or "\27[31m[ Unknown Version ]\27[0m"
		else
			installed = "\27[31m[ Not Installed ]\27[0m"
		end

		local homepage = pkg.homepage or "No homepage"
		local description = pkg.description or "No description"
		local license = pkg.license or "unknown"
		print("\27[1;32m*\27[0m  " .. repo .. "/" .. pkg.name .. " " .. masked)
		print("      Available: " .. latest)
		print("      Installed: " .. installed)
		print("      Homepage: " .. homepage)
		print("      Description: " .. description)
		print("      License: " .. license)
		print()
	end
end

function search.get_installed_version(package_name)
	local config = require("src.config")
	local db_file = config.DB_PATH .. "/" .. package_name:gsub("%.", "-")
	local f = io.open(db_file, "r")
	if not f then
		return nil
	end
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

function search.scan_repo(repo_name, repo_path, pattern, results)
	pattern = pattern or ""
	if not repo_path or repo_path == "" then
		return
	end
	local cmd = "find " .. repo_path .. " -name manifest.lua"
	local handle = io.popen(cmd)
	if not handle then
		return
	end
	for line in handle:lines() do
		local manifest_path = line:match("^%s*(.-)%s*$")
		if manifest_path and manifest_path ~= "" then
			local ok, manifest = pcall(function()
				return loader.loadfile(manifest_path)
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
