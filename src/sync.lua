local sync = {}
local config = require("src.config")
function sync.update_repos()
	print("syncing repositories...")
	for repo_name, repo_entry in pairs(config.repos) do
		local repo_path = config.ensure_repo(repo_name)
		if repo_path then
			print("  " .. repo_name .. " -> " .. repo_path)
			sync.update_repo(repo_path)
		else
			print("  " .. repo_name .. " (not a git repo, skipping)")
		end
	end
	print("sync complete.")
end

function sync.update_repo(repo_path)
	local git_dir = repo_path .. "/.git"
	local f = io.open(git_dir .. "/config", "r")
	if f then
		f:close()
		local cmd = "cd " .. repo_path .. " && git pull"
		local ok, _, code = os.execute(cmd)
		if not ok or code ~= 0 then
			print("    Warning: failed to update repository")
		end
	else
		print("    Not a git repository, skipping...")
	end
end

return sync
