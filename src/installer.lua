local installer = {}
local config = require("src.config")
local fetcher = require("src.fetcher")
local builder = require("src.builder")
local resolver = require("src.resolver")
local loader = require("src.loader")
function installer.install(manifest, args)
	if os.getenv("PKGLET_DEBUG") == "1" then
		print("DEBUG: args =")
		for k, v in pairs(args) do
			print("  " .. k .. " = " .. tostring(v))
		end
	end

	if args.bootstrap_to then
		config.set_bootstrap_root(args.bootstrap_to)
		print("Bootstrap mode: installing to " .. config.ROOT)
	end

	local conflict = require("src.conflict")
	local conflicts = conflict.check_conflicts(manifest.name, manifest)

	if #conflicts > 0 then
		local can_resolve = conflict.resolve_conflicts(manifest.name, conflicts, args.force)
		if not can_resolve then
			error("installation aborted due to unresolvable conflicts")
		end
	end

	if args.options.hook then
		return installer.run_single_hook(manifest, args)
	end

	if resolver.is_installed(manifest.name) and not args.force then
		print("Package already installed: " .. manifest.name)
		return
	end

	local packages_to_install

	if args.nodeps then
		packages_to_install = {}
		if not resolver.is_installed(manifest.name) or args.force then
			packages_to_install[manifest.name] = manifest.version
		end
	else
		packages_to_install = installer.resolve_dependencies(manifest, {}, args.force)

		if args.options and args.options.with_optional then
			print("Installing optional dependencies...")
			local optional_packages = installer.resolve_optional_dependencies(manifest, {})
			for name, version in pairs(optional_packages) do
				if not packages_to_install[name] then
					packages_to_install[name] = version
				end
			end
		end
	end

	if installer.count_keys(packages_to_install) > 0 then
		print("Packages to install:")
		for name, version in pairs(packages_to_install) do
			local pkg_manifest = loader.load_manifest(name)
			local build_type = installer.determine_build_type(pkg_manifest, args.build_from, name, args.package_build_types)
			local build_type_label = build_type == "source" and "[S]" or "[B]"
			local label = "\27[34m" .. build_type_label .. "\27[0m"
			print("  " .. label .. " \27[7m" .. name .. "\27[0m " .. version)
		end
		print("")
	else
		if args.nodeps then
			print("Package already installed.")
		else
			print("All dependencies already installed.")
		end
		print("")
		return
	end

	if not args.noask then
		io.write("Proceed with installation? \27[7m[Y/n]\27[0m ")
		local response = io.read()
		if response and response:lower():sub(1, 1) == "n" then
			print("Installation cancelled.")
			return
		end
	end

    os.execute("mkdir -p " .. config.ROOT)
	local install_order = {}
	for name, version in pairs(packages_to_install) do
		table.insert(install_order, name)
	end

	for _, name in ipairs(install_order) do
		local pkg_manifest = loader.load_manifest(name)
		print("Installing " .. pkg_manifest.name .. " " .. pkg_manifest.version)
		local build_type = installer.determine_build_type(pkg_manifest, args.build_from, name, args.package_build_types)
		print("Build type: " .. build_type)
		local merged_opts = {}
		if args.package_options and args.package_options[name] then
			for k, v in pairs(args.package_options[name]) do
				merged_opts[k] = v
			end
		end
		if args.options then
			for k, v in pairs(args.options) do
				merged_opts[k] = v
			end
		end
		local options = installer.merge_options(pkg_manifest, merged_opts)
		local build_dir = config.BUILD_PATH .. "/" .. pkg_manifest.name
		local temp_install_dir = config.TEMP_INSTALL_PATH .. "/" .. pkg_manifest.name
		os.execute("rm -rf " .. build_dir)
		os.execute("mkdir -p " .. build_dir)
		os.execute("rm -rf " .. temp_install_dir)
		os.execute("mkdir -p " .. temp_install_dir)
		local source_spec
		if build_type == "source" then
			source_spec = pkg_manifest.sources.source
		else
			source_spec = pkg_manifest.sources.binary
		end
		if source_spec then
			fetcher.fetch(source_spec, build_dir)
		end
		builder.build(pkg_manifest, build_dir, build_type, options)
		local files_list = installer.copy_from_temp(pkg_manifest)
		installer.record_installation(pkg_manifest, files_list)
		print("Successfully installed " .. pkg_manifest.name)
	end
end

function installer.uninstall(manifest)
	print("Uninstalling " .. manifest.name)
	if not resolver.is_installed(manifest.name) then
		print("Package not installed: " .. manifest.name)
		return
	end

	if manifest.uninstall then
		local build_dir = config.BUILD_PATH .. "/" .. manifest.name
		local uninstall_fn = manifest.uninstall()
		local hooks = {
			pre_uninstall = nil,
			post_uninstall = nil,
		}

		local function hook(name)
			return function(fn)
				hooks[name] = fn
			end
		end

		uninstall_fn(hook)
		if hooks.pre_uninstall then
			hooks.pre_uninstall()
		end
		installer.remove_files(manifest)
		if hooks.post_uninstall then
			hooks.post_uninstall()
		end
	else
		installer.remove_files(manifest)
	end

	installer.remove_installation_record(manifest)
	print("Successfully uninstalled " .. manifest.name)
end

function installer.determine_build_type(manifest, preference, pkg_name, package_build_types)
	if preference == "source" then
		return "source"
	elseif preference == "binary" then
		return "binary"
	end

	if package_build_types and pkg_name and package_build_types[pkg_name] then
		return package_build_types[pkg_name]
	end

	local make_opts = config.get_make_opts()
	if make_opts.default_build_mode == "source" then
		if manifest.sources.source then
			return "source"
		end
	elseif make_opts.default_build_mode == "binary" then
		if manifest.sources.binary then
			return "binary"
		end
	end

	if manifest.sources.binary then
		return "binary"
	elseif manifest.sources.source then
		return "source"
	end

	error("no valid source or binary available")
end

function installer.merge_options(manifest, cli_options)
	local options = {}
	if manifest.options then
		for name, opt in pairs(manifest.options) do
			options[name] = opt.default
		end
	end
	if config.package_options[manifest.name] then
		for opt, _ in pairs(config.package_options[manifest.name]) do
			options[opt] = true
		end
	end
	if cli_options then
		for opt, value in pairs(cli_options) do
			if value == "true" then
				options[opt] = true
			elseif value == "false" then
				options[opt] = false
			else
				options[opt] = value
			end
		end
	end
	return options
end

function installer.record_installation(manifest, files_list)
	local db_file = config.DB_PATH .. "/" .. manifest.name:gsub("%.", "-")
	local f = io.open(db_file, "w")
	if f then
		f:write("name=" .. manifest.name .. "\n")
		f:write("version=" .. manifest.version .. "\n")
		f:write("installed=" .. os.time() .. "\n")
		f:write("manifest_path=" .. (manifest._path or "") .. "\n")
		if files_list then
			for _, file in ipairs(files_list) do
				f:write("file=" .. file .. "\n")
			end
		end
		f:close()
	end
end

function installer.remove_installation_record(manifest)
	local db_file = config.DB_PATH .. "/" .. manifest.name:gsub("%.", "-")
	os.remove(db_file)
end

function installer.copy_from_temp(manifest)
	local temp_path = config.TEMP_INSTALL_PATH .. "/" .. manifest.name
	local dest_path = config.ROOT
    local extras = ""
	print("Copying files from temporary location...")
    if manifest._backup and manifest._backup ~= "" then
        extras = extras.." --backup="..manifest._backup
    end
    if manifest._extras and manifest._extras ~= "" then
        extras = extras.." "..manifest._extras
    end
	os.execute("cp -rn " .. temp_path .. "/* " .. dest_path .. "/ "..extras)
	local files_list = {}
	local handle = io.popen("cd " .. temp_path .. " && find . -type f -o -type l")
	if handle then
		for line in handle:lines() do
			local file_path = line:match("^%.(.+)$")
			if file_path then
				table.insert(files_list, file_path)
			end
		end
		handle:close()
	end
	return files_list
end

function installer.get_dependencies(manifest)
	local version_module = require("src.version")
	local deps = {}
	if manifest.depends then
		for _, dep in ipairs(manifest.depends) do
			if type(dep) == "string" then
				local parsed = version_module.parse_dependency(dep)
				deps[parsed.name] = parsed.constraint
			elseif type(dep) == "table" then
				deps[dep.name] = dep.constraint or "*"
			end
		end
	end
	if manifest.build_depends then
		for _, dep in ipairs(manifest.build_depends) do
			if type(dep) == "string" then
				local parsed = version_module.parse_dependency(dep)
				deps[parsed.name] = parsed.constraint
			elseif type(dep) == "table" then
				deps[dep.name] = (dep.constraint or "*") .. ":build"
			end
		end
	end
	if manifest.optional_depends then
		for _, dep in ipairs(manifest.optional_depends) do
			if type(dep) == "string" then
				local parsed = version_module.parse_dependency(dep)
				deps[parsed.name] = (parsed.constraint or "*") .. ":optional"
			elseif type(dep) == "table" then
				deps[dep.name] = ((dep.constraint or "*") .. ":optional")
			end
		end
	end
	return deps
end

function installer.resolve_dependencies(manifest, visited, force)
	local version_module = require("src.version")
	visited = visited or {}
	local packages_to_install = {}

	if visited[manifest.name] then
		return {}
	end
	visited[manifest.name] = true

	if not resolver.is_installed(manifest.name) or force then
		packages_to_install[manifest.name] = manifest.version
	end

	local deps = installer.get_dependencies(manifest)
	local conflict = require("src.conflict")
	local resolved_deps = conflict.resolve_virtual_dependencies(deps)

	for dep_name, dep_constraint in pairs(resolved_deps) do
		local is_build_dep = dep_constraint:match(":build$") ~= nil
		local is_optional_dep = dep_constraint:match(":optional$") ~= nil

		if is_build_dep then
			dep_constraint = dep_constraint:gsub(":build$", "")
		elseif is_optional_dep then
			dep_constraint = dep_constraint:gsub(":optional$", "")
		end

		if not resolver.is_installed(dep_name) and not visited[dep_name] then
			if is_optional_dep then
				print("Optional dependency " .. dep_name .. " not installed, skipping")
			else
				local available_versions = version_module.get_available_versions(dep_name)
				local selected_version = version_module.highest_satisfying(available_versions, dep_constraint)

				if not selected_version then
					error("no satisfying version found for " .. dep_name .. " " .. dep_constraint)
				end

				local dep_manifest = loader.load_manifest(dep_name)
				dep_manifest.version = selected_version
				local dep_packages = installer.resolve_dependencies(dep_manifest, visited, force)
				for name, version in pairs(dep_packages) do
					packages_to_install[name] = version
				end
				if not visited[dep_name] then
					packages_to_install[dep_name] = selected_version
				end
			end
		elseif resolver.is_installed(dep_name) then
			local current_version = installer.get_installed_version(dep_name)
			if not version_module.satisfies(dep_constraint, current_version) then
				if is_optional_dep then
					print(
						"Warning: installed optional dependency "
							.. dep_name
							.. " ("
							.. current_version
							.. ") does not satisfy constraint "
							.. dep_constraint
					)
				else
					error(
						"installed version of "
							.. dep_name
							.. " ("
							.. current_version
							.. ") does not satisfy constraint "
							.. dep_constraint
					)
				end
			end
		end
	end

	return packages_to_install
end

function installer.count_keys(table)
	local count = 0
	for _ in pairs(table) do
		count = count + 1
	end
	return count
end

function installer.remove_files(manifest)
	print("Removing files...")
	local db_file = config.DB_PATH .. "/" .. manifest.name:gsub("%.", "-")
	local f = io.open(db_file, "r")
	local files = {}
	if f then
		for line in f:lines() do
			local key, value = line:match("^([^=]+)=(.+)$")
			if key == "file" then
				table.insert(files, value)
			end
		end
		f:close()
	end

	for _, file in ipairs(files) do
		local full_path = config.ROOT .. "/" .. file
		os.execute("rm -f " .. full_path)
	end

	local temp_path = config.TEMP_INSTALL_PATH .. "/" .. manifest.name
	os.execute("rm -rf " .. temp_path)

	if #files > 0 then
		print("Removed " .. #files .. " files")
	end
end

function installer.run_single_hook(manifest, args)
	if os.getenv("PKGLET_DEBUG") == "1" then
		print("options =")
		for k, v in pairs(args.options) do
			print("  " .. k .. " = " .. tostring(v))
		end
	end

	local build_type = installer.determine_build_type(manifest, args.build_from)
	local options = installer.merge_options(manifest, args.options)
	local build_dir = config.BUILD_PATH .. "/" .. manifest.name
	local temp_install_dir = config.TEMP_INSTALL_PATH .. "/" .. manifest.name

	os.execute("rm -rf " .. build_dir)
	os.execute("mkdir -p " .. build_dir)
	os.execute("rm -rf " .. temp_install_dir)
	os.execute("mkdir -p " .. temp_install_dir)

	local source_spec
	if build_type == "source" then
		source_spec = manifest.sources.source
	else
		source_spec = manifest.sources.binary
	end

	if source_spec then
		fetcher.fetch(source_spec, build_dir)
	end

	local build_fn
	if build_type == "source" then
		build_fn = manifest.source()
	else
		build_fn = manifest.binary()
	end

	local hooks = {}

	local function hook(name)
		return function(fn)
			hooks[name] = fn
		end
	end

	build_fn(hook)

	local hook_name = args.options.hook
	if hook_name == "prepare" and hooks.prepare then
		print("Running prepare hook...")
		hooks.prepare()
	elseif hook_name == "build" and hooks.build then
		print("Running build hook...")
		hooks.build()
	elseif hook_name == "pre_install" and hooks.pre_install then
		print("Running pre_install hook...")
		hooks.pre_install()
	elseif hook_name == "install" and hooks.install then
		print("Running install hook...")
		hooks.install()
		local files_list = installer.copy_from_temp(manifest)
		installer.record_installation(manifest, files_list)
	elseif hook_name == "post_install" and hooks.post_install then
		local files_list = installer.copy_from_temp(manifest)
		installer.record_installation(manifest, files_list)
		print("Running post_install hook...")
		hooks.post_install()
	else
		print("Hook '" .. hook_name .. "' not found or not available")
		return
	end

	print("Hook '" .. tostring(hook_name) .. "' completed successfully")
end

function installer.resolve_optional_dependencies(manifest, visited)
	local version_module = require("src.version")
	local loader = require("src.loader")
	visited = visited or {}
	local optional_packages = {}
	if visited[manifest.name] then
		return {}
	end
	visited[manifest.name] = true
	if manifest.optional_depends then
		for _, dep in ipairs(manifest.optional_depends) do
			local dep_name, dep_constraint
			if type(dep) == "string" then
				local parsed = version_module.parse_dependency(dep)
				dep_name = parsed.name
				dep_constraint = parsed.constraint
			elseif type(dep) == "table" then
				dep_name = dep.name
				dep_constraint = dep.constraint or "*"
			end
			if not resolver.is_installed(dep_name) and not visited[dep_name] then
				local available_versions = version_module.get_available_versions(dep_name)
				local selected_version = version_module.highest_satisfying(available_versions, dep_constraint)
				if selected_version then
					local dep_manifest = loader.load_manifest(dep_name)
					dep_manifest.version = selected_version
					local dep_optional = installer.resolve_optional_dependencies(dep_manifest, visited)
					for name, version in pairs(dep_optional) do
						optional_packages[name] = version
					end
					if not visited[dep_name] then
						optional_packages[dep_name] = selected_version
					end
				end
			end
		end
	end
	return optional_packages
end

function installer.get_installed_version(package_name)
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

function installer.get_all_installed()
	local packages = {}
	local handle = io.popen("ls " .. config.DB_PATH .. " 2>/dev/null")
	if handle then
		for line in handle:lines() do
			if line and line ~= "" then
				local name = line:gsub("%-", ".")
				table.insert(packages, name)
			end
		end
		handle:close()
	end
	return packages
end

function installer.upgrade_all(args)
	local version_module = require("src.version")
	local loader = require("src.loader")
	local resolver = require("src.resolver")

	local installed = installer.get_all_installed()
	if #installed == 0 then
		print("No packages installed.")
		return
	end

	local packages_to_upgrade = {}
	for _, package_name in ipairs(installed) do
		local current_version = installer.get_installed_version(package_name)
		local latest_version = version_module.get_latest_version(package_name, current_version)
		if latest_version and latest_version ~= current_version then
			table.insert(
				packages_to_upgrade,
				{ name = package_name, current = current_version, latest = latest_version }
			)
		end
	end

	if #packages_to_upgrade == 0 then
		print("All packages are up to date.")
		return
	end

	print("Packages to upgrade:")
	for _, pkg in ipairs(packages_to_upgrade) do
		print("  " .. pkg.name .. " " .. pkg.current .. " -> " .. pkg.latest)
	end
	print("")

	if not args.noask then
		io.write("Proceed with upgrade? \27[7m[Y/n]\27[0m ")
		local response = io.read()
		if response and response:lower():sub(1, 1) == "n" then
			print("Upgrade cancelled.")
			return
		end
	end

	for _, pkg in ipairs(packages_to_upgrade) do
		print("Upgrading " .. pkg.name .. " from " .. pkg.current .. " to " .. pkg.latest)
		local manifest = loader.load_manifest(pkg.name)
		manifest.version = pkg.latest
		installer.uninstall(manifest)
		installer.install(manifest, args)
	end
end

function installer.upgrade(package_name, args)
	local version_module = require("src.version")
	local loader = require("src.loader")
	local resolver = require("src.resolver")
	if not resolver.is_installed(package_name) then
		print("Package not installed: " .. package_name)
		return
	end
	local current_version = installer.get_installed_version(package_name)
	local latest_version = version_module.get_latest_version(package_name, current_version)
	if not latest_version then
		print("Package " .. package_name .. " is already up to date at version " .. current_version)
		return
	end
	print("Upgrading " .. package_name .. " from " .. current_version .. " to " .. latest_version)
	local manifest = loader.load_manifest(package_name)
	manifest.version = latest_version
	installer.uninstall(manifest)
	installer.install(manifest, args)
end

function installer.downgrade(package_name, target_version, args)
	local version_module = require("src.version")
	local loader = require("src.loader")
	local resolver = require("src.resolver")
	if not resolver.is_installed(package_name) then
		print("Package not installed: " .. package_name)
		return
	end
	local current_version = installer.get_installed_version(package_name)
	print("Downgrading " .. package_name .. " from " .. current_version .. " to " .. target_version)
	local manifest = loader.load_manifest(package_name)
	manifest.version = target_version
	installer.uninstall(manifest)
	installer.install(manifest, args)
end

return installer
