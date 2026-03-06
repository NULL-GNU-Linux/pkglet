local loader = {}
local config = require("src.config")
function loader.find_manifest(package_name)
	local repo, pkg_name = package_name:match("^([^/]+)/(.+)$")
	if repo and pkg_name then
		local repo_entry = config.repos[repo]
		if repo_entry then
			local repo_path = config.ensure_repo(repo)
			if repo_path then
				local manifest_path = repo_path .. "/" .. pkg_name:gsub("%.", "/") .. "/manifest.lua"
				local f = io.open(manifest_path, "r")
				if f then
					f:close()
					return manifest_path
				end
			end
		end
		error("package not found: " .. package_name)
	end

	for repo_name, repo_entry in pairs(config.repos) do
		local repo_path = config.ensure_repo(repo_name)
		if repo_path then
			local manifest_path = repo_path .. "/" .. package_name:gsub("%.", "/") .. "/manifest.lua"
			local f = io.open(manifest_path, "r")
			if f then
				f:close()
				return manifest_path
			end
		end
	end
	error("package not found: " .. package_name)
end

function loader.loadfile(manifest_path)
	local env = {
		make = function() end,
		cmake = function() end,
		exec = function() end,
		ninja = function() end,
		meson = function() end,
		CONFIG = {},
		ROOT = "/",
		OPTIONS = {},
		ARCH = "x86_64",
	}
	setmetatable(env, { __index = _G })
	local chunk, err = loadfile(manifest_path, "t", env)
	if not chunk then
		error("failed to load manifest: " .. err)
	end
	chunk()
	if not env.pkg then
		error("manifest missing 'pkg' table")
	end
	local manifest = env.pkg
	manifest._path = manifest_path
	manifest._env = env
	loader.validate_manifest(manifest)
	return manifest
end

function loader.load_manifest(package_name)
	local manifest_path = loader.find_manifest(package_name)
	local manifest = loader.loadfile(manifest_path)
	return manifest
end

function loader.validate_manifest(manifest)
	local required = { "name", "version", "description", "license" }
	for _, field in ipairs(required) do
		if not manifest[field] then
			error("manifest missing required field: " .. field)
		end
	end

	if config.masked_packages[manifest.name] then
		error("package is masked: " .. manifest.name)
	end
	if
		manifest.repository
		and config.masked_packages[manifest.repository]
		and config.masked_packages[manifest.repository][manifest.name]
	then
		error("package is masked: " .. manifest.repository .. "/" .. manifest.name)
	end
end

function loader.print_info(manifest)
	print("Name:        " .. manifest.name)
	print("Version:     " .. manifest.version)
	print("Description: " .. manifest.description)
	if manifest.maintainer then
		print("Maintainer:  " .. manifest.maintainer)
	end
	print("License:     " .. manifest.license)
	if manifest.homepage then
		print("Homepage:    " .. manifest.homepage)
	end

	if manifest.depends and #manifest.depends > 0 then
		print("Depends:     " .. table.concat(manifest.depends, ", "))
	end

	if manifest.conflicts and #manifest.conflicts > 0 then
		print("Conflicts:   " .. table.concat(manifest.conflicts, ", "))
	end

	if manifest.provides and #manifest.provides > 0 then
		print("Provides:    " .. table.concat(manifest.provides, ", "))
	end

	if manifest.options then
		print("\nOptions:")
		for name, opt in pairs(manifest.options) do
			local desc = opt.description or ""
			local default = opt.default and "true" or "false"
			print("  " .. name .. " (default: " .. default .. ") - " .. desc)
		end
	end
end

return loader
