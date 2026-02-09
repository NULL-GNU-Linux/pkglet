--- Repository synchronization module for managing package repositories
--
-- This module handles the synchronization of all configured package repositories
-- by performing git pull operations on each repository. It checks if each
-- repository path contains a valid git repository before attempting to update,
-- and provides appropriate status messages and warnings when operations fail.
-- The module is essential for keeping the local package database up-to-date
-- with the latest changes from remote repositories.
-- @module sync

local sync = {}
local config = require("src.config")

--- Update all configured repositories in sequence
--
-- This function iterates through all repositories defined in the configuration
-- and attempts to update each one using git pull. It performs validation
-- to ensure each directory is a valid git repository before attempting
-- the update operation. The function provides detailed progress output
-- and handles errors gracefully by continuing with other repositories
-- if one fails to update.
--
-- This is typically called during 'pkglet S' command execution to ensure
-- all package repositories are synchronized with their remote counterparts.
function sync.update_repos()
	print("syncing repositories...")
	for repo_name, repo_path in pairs(config.repos) do
		print("  " .. repo_name .. " -> " .. repo_path)
		sync.update_repo(repo_path)
	end
	print("sync complete.")
end

--- Update a single repository using git pull or mirror sync
--
-- Updates a single repository by first validating that it's a proper git
-- repository by checking for the existence of .git/config file. If the
-- validation passes, it executes 'git pull' in the repository directory.
-- For non-git repositories, it attempts to sync using configured mirrors.
-- The function handles both success and failure cases gracefully,
-- providing appropriate warning messages without interrupting the overall
-- synchronization process.
--
-- @param repo_name string The name of the repository to update
function sync.update_repo(repo_name)
	local repo_path = config.repos[repo_name]
	local git_dir = repo_path .. "/.git"
	local f = io.open(git_dir .. "/config", "r")
	if f then
		f:close()
		local cmd = "cd " .. repo_path .. " && git pull"
		local ok, _, code = os.execute(cmd)
		if not ok or code ~= 0 then
			print("    Warning: failed to update repository, trying mirrors...")
			sync.sync_from_mirrors(repo_name)
		end
	else
		print("    Not a git repository, syncing from mirrors...")
		sync.sync_from_mirrors(repo_name)
	end
end

--- Sync repository from configured mirrors
--
-- Synchronizes a repository by downloading manifests from configured mirrors.
-- This is used for remote repositories that aren't git checkouts. The function
-- attempts to download from each mirror until one succeeds, providing
-- redundancy and fallback capabilities for remote package sources.
--
-- @param repo_name string The name of the repository to sync from mirrors
function sync.sync_from_mirrors(repo_name)
	local repo_path = config.repos[repo_name]
	local mirrors = config.get_repo_mirrors(repo_name)
	local sources = {repo_path}
	
	for _, mirror in ipairs(mirrors) do
		table.insert(sources, mirror)
	end
	
	local success = false
	for i, source in ipairs(sources) do
		print("    Trying source " .. i .. "/" .. #sources .. ": " .. source)
		
		if source:match("^https?://") then
			if sync.sync_from_remote_mirror(repo_name, source, repo_path) then
				success = true
				break
			end
		else
			if sync.validate_local_source(source) then
				success = true
				break
			end
		end
	end
	
	if success then
		print("    Repository synced successfully")
	else
		print("    Warning: failed to sync from all sources")
	end
end

--- Sync repository from a remote mirror URL
--
-- Downloads and updates manifest files from a remote HTTP/HTTPS mirror.
-- This function handles the actual downloading of package manifests
-- and repository metadata from remote sources.
--
-- @param repo_name string Name of the repository
-- @param mirror_url string URL of the remote mirror
-- @param local_path string Local path to store synchronized files
-- @return boolean True if sync was successful
function sync.sync_from_remote_mirror(repo_name, mirror_url, local_path)
	local temp_dir = "/tmp/pkglet-sync-" .. repo_name .. "-" .. math.random(1000, 9999)
	os.execute("mkdir -p " .. temp_dir)
	
	local repo_list_file = temp_dir .. "/repo-list.txt"
	local cmd = "wget -q -O " .. repo_list_file .. " " .. mirror_url .. "/packages.txt 2>/dev/null"
	local ok, _, code = os.execute(cmd)
	
	if not ok or code ~= 0 then
		os.execute("rm -rf " .. temp_dir)
		return false
	end
	
	local repo_list = io.open(repo_list_file, "r")
	if not repo_list then
		os.execute("rm -rf " .. temp_dir)
		return false
	end
	
	local package_count = 0
	for package_path in repo_list:lines() do
		package_path = package_path:match("^%s*(.-)%s*$")
		if package_path and package_path ~= "" then
			local url = mirror_url .. "/" .. package_path
			local local_file = local_path .. "/" .. package_path
			local local_dir = local_file:match("^(.+)/[^/]+$")
			
			os.execute("mkdir -p " .. local_dir)
			
			local download_cmd = "wget -q -O " .. local_file .. " " .. url
			local dl_ok, dl_code = os.execute(download_cmd)
			
			if dl_ok and dl_code == 0 then
				package_count = package_count + 1
			else
				print("      Warning: failed to download " .. package_path)
			end
		end
	end
	repo_list:close()
	os.execute("rm -rf " .. temp_dir)
	
	if package_count > 0 then
		print("      Downloaded " .. package_count .. " package files")
		return true
	else
		return false
	end
end

--- Validate that a local repository source exists and is readable
--
-- Checks if a local repository path contains valid package manifests.
-- This is used for validation before attempting to use a source for
-- package installation or synchronization.
--
-- @param source_path string Path to validate
-- @return boolean True if source appears valid
function sync.validate_local_source(source_path)
	local test_path = source_path .. "/manifest.lua"
	local f = io.open(test_path, "r")
	if f then
		f:close()
		return true
	end
	
	local cmd = "find " .. source_path .. " -name manifest.lua 2>/dev/null | head -n 1"
	local handle = io.popen(cmd)
	local result = handle:read("*a")
	handle:close()
	
	return result and result:trim() ~= ""
end

--- Generate repository manifest for mirror publishing
--
-- Creates a packages.txt file listing all package manifest paths
-- in a repository. This file is used by mirror synchronization
-- to know which files to download.
--
-- @param repo_path string Path to repository
function sync.generate_repo_manifest(repo_path)
	local manifest_file = repo_path .. "/packages.txt"
	local f = io.open(manifest_file, "w")
	if not f then return end
	
	local cmd = "find " .. repo_path .. " -name manifest.lua -type f | sort"
	local handle = io.popen(cmd)
	
	for line in handle:lines() do
		line = line:match("^%s*(.-)%s*$")
		if line then
			local relative_path = line:sub(#repo_path + 2)
			f:write(relative_path .. "\n")
		end
	end
	handle:close()
	f:close()
	
	print("Generated repository manifest: " .. manifest_file)
end

return sync
