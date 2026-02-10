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
local progress = require("src.progress")

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
	local repo_list = {}
	for repo_name, _ in pairs(config.repos) do
		table.insert(repo_list, repo_name)
	end
	
	progress.start_operation("repository synchronization")
	
	for i, repo_name in ipairs(repo_list) do
		local repo_path = config.repos[repo_name]
		progress.update_progress(i, #repo_list, "Syncing repositories")
		progress.update_status("Syncing " .. repo_name .. " -> " .. repo_path)
		sync.update_repo(repo_path)
	end
	
	progress.finish_operation(true, "Repository synchronization complete")
end

--- Update a single repository using git pull
--
-- Updates a single repository by first validating that it's a proper git
-- repository by checking for the existence of .git/config file. If the
-- validation passes, it executes 'git pull' in the repository directory.
-- The function handles both success and failure cases gracefully,
-- providing appropriate warning messages without interrupting the overall
-- synchronization process.
--
-- @param repo_path string The path of the repository to update
function sync.update_repo(repo_path)
	local git_dir = repo_path .. "/.git"
	local f = io.open(git_dir .. "/config", "r")
	if f then
		f:close()
		local cmd = "cd " .. repo_path .. " && git pull"
		local ok, _, code = os.execute(cmd)
		if not ok or code ~= 0 then
			progress.update_status("Warning: failed to update repository")
		else
			progress.update_status("Successfully updated repository")
		end
	else
		progress.update_status("Not a git repository, skipping...")
	end
end



return sync
