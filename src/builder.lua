local builder = {}
local config = require("src.config")
function builder.build(manifest, build_dir, build_type, options)
	local make_opts = config.get_make_opts()
	local env = manifest._env
	env.OPTIONS = options or {}
	env.INSTALL = config.TEMP_INSTALL_PATH.."/"..manifest.name
	env.make = function(extra_args, is_build, destvar, prefix)
		return builder.make_wrapper(build_dir, make_opts, extra_args, is_build, destvar, prefix)
	end
	env.cmake = function(args)
		return builder.cmake_wrapper(build_dir, args)
	end
	env.configure = function(args, name)
		return builder.configure_wrapper(build_dir, args, name)
	end
	env.ninja = function(args)
		return builder.ninja_wrapper(build_dir, make_opts, args)
	end
	env.install = function(args, command)
		return builder.install_wrapper(build_dir, args, command)
	end
	env.meson = function(args)
		return builder.meson_wrapper(build_dir, args)
	end
	env.cargo = function(args)
		return builder.cargo_wrapper(build_dir, make_opts, args)
	end
	env.go = function(args)
		return builder.go_wrapper(build_dir, args)
	end
	env.npm = function(args)
		return builder.npm_wrapper(build_dir, args)
	end
	env.mvn = function(args)
		return builder.mvn_wrapper(build_dir, args)
	end
	env.gradle = function(args)
		return builder.gradle_wrapper(build_dir, args)
	end
	env.scons = function(args)
		return builder.scons_wrapper(build_dir, make_opts, args)
	end
	env.bazel = function(args)
		return builder.bazel_wrapper(build_dir, args)
	end
	env.patch = function(patch_file, args)
		return builder.patch_wrapper(build_dir, patch_file, args)
	end
	env.git = function(args)
		return builder.git_wrapper(build_dir, args)
	end
	env.wget = function(url, dest, args)
		return builder.wget_wrapper(build_dir,url, dest, args)
	end
	env.curl = function(url, dest, args)
		return builder.curl_wrapper(build_dir,url, dest, args)
	end
	env.tar = function(archive, dest, args)
		return builder.tar_wrapper(build_dir,archive, dest, args)
	end
	env.unzip = function(archive, dest, args)
		return builder.unzip_wrapper(build_dir,archive, dest, args)
	end
	env.python = function(args)
		return builder.python_wrapper(build_dir,build_dir, args)
	end
	env.setuid = function(file, owner, mode)
		return builder.setuid_wrapper(build_dir,file, owner, mode)
	end
	local f = io.popen("uname -m")
	local arch = f:read("*l")
	f:close()
	env.ARCH = arch
	env.exec = function(command)
        local cmd = "cd " ..  build_dir .. " && " .. command
        print("\27[7m-> " .. cmd .. "\27[0m")
        os.execute(cmd)
    end
	env.pkglet = {
		install = function(name, options)
			local installer = require("src.installer")
			local loader = require("src.loader")
			local cli = require("src.cli")
			local args = cli.parse({ "install", name })
			args.noask = config.noask
			if options then
				for k, v in pairs(options) do
					if k == "noask" then
						args.noask = v
					else
						args.options[k] = v
					end
				end
			end
			return installer.install(loader.load_manifest(name), args)
		end,
		uninstall = function(name, options)
			local installer = require("src.installer")
			local loader = require("src.loader")
			local manifest = loader.load_manifest(name)
			local noask = config.noask
			if options and options.noask ~= nil then
				noask = options.noask
			end
			if not noask then
				io.write("Uninstall " .. name .. "? \27[7m[Y/n]\27[0m ")
				local response = io.read()
				if response and response:lower():sub(1, 1) == "n" then
					print("Uninstall cancelled.")
					return
				end
			end
			return installer.uninstall(manifest)
		end,
		sync = function()
			local sync = require("src.sync")
			return sync.update_repos()
		end,
		info = function(name)
			local loader = require("src.loader")
			local manifest = loader.load_manifest(name)
			return loader.print_info(manifest)
		end,
	}
	env.ROOT = config.ROOT
	env.CONFIG = config
	local build_fn
	if build_type == "source" then
		if not manifest.source then
			error("package has no source build function")
		end
		build_fn = manifest.source()
	else
		if not manifest.binary then
			error("package has no binary build function")
		end
		build_fn = manifest.binary()
	end
	local hooks = {
		prepare = nil,
		build = nil,
		pre_install = nil,
		install = nil,
		post_install = nil,
	}

	local function hook(name)
		return function(fn)
			hooks[name] = fn
		end
	end
	build_fn(hook)
	local old_dir = os.getenv("PWD") or "."
	os.execute("cd " .. build_dir)
	if hooks.prepare then
		hooks.prepare()
	end
	if hooks.build then
		hooks.build()
	end
	if hooks.pre_install then
		hooks.pre_install()
	end
	if hooks.install then
		hooks.install()
	end
	if hooks.post_install then
		hooks.post_install()
	end
	os.execute("cd " .. old_dir)
	return hooks
end

function builder.make_wrapper(build_dir, make_opts, extra_args, is_build, destvar, prefix)
    prefix = prefix or ""
    destvar = destvar or "DESTDIR"
	local cmd = "cd " .. build_dir .. " && " .. prefix .. " make"
	if is_build == nil or is_build == true then
		if make_opts.jobs then
			cmd = cmd .. " -j" .. make_opts.jobs
		end
		if make_opts.load then
			cmd = cmd .. " -l" .. make_opts.load
		end
		if make_opts.extra then
			cmd = cmd .. " " .. make_opts.extra
		end
	else
		cmd = cmd .. " " .. destvar .. "=" .. config.TEMP_INSTALL_PATH .. "/" .. build_dir:match("([^/]+)$") .. " install"
	end
	if extra_args then
		for _, arg in ipairs(extra_args) do
			cmd = cmd .. " " .. arg
		end
	end

print("\27[7m-> " .. cmd .. "\27[0m")
	local ok, _, code = os.execute(cmd)
	if not ok or code ~= 0 then
		error("make failed")
	end
end

function builder.cmake_wrapper(build_dir, args)
	local cmd = "cd " .. build_dir .. " && cmake"
	if args then
		for _, arg in ipairs(args) do
			cmd = cmd .. " " .. arg
		end
	end
print("\27[7m-> " .. cmd .. "\27[0m")
	local ok, _, code = os.execute(cmd)
	if not ok or code ~= 0 then
		error("cmake failed")
	end
end

function builder.configure_wrapper(build_dir, args, name)
    name = name or "configure"
	local cmd = "cd " .. build_dir .. " && ./" .. name .. " "
	if args then
		for _, arg in ipairs(args) do
			cmd = cmd .. " " .. arg
		end
	end
print("\27[7m-> " .. cmd .. "\27[0m")
	local ok, _, code = os.execute(cmd)
	if not ok or code ~= 0 then
		error("configure failed")
	end
end

function builder.ninja_wrapper(build_dir, make_opts, args)
	local cmd = "cd " .. build_dir .. " && ninja"
	if make_opts.jobs then
		cmd = cmd .. " -j" .. make_opts.jobs
	end
	if make_opts.load then
		cmd = cmd .. " -l" .. make_opts.load
	end
	if args then
		for _, arg in ipairs(args) do
			cmd = cmd .. " " .. arg
		end
	end

print("\27[7m-> " .. cmd .. "\27[0m")
	local ok, _, code = os.execute(cmd)
	if not ok or code ~= 0 then
		error("ninja failed")
	end
end

function builder.install_wrapper(build_dir, args, command)
    command = command or "install"
	local cmd = "cd " .. build_dir .. " && " .. command
	local package_name = build_dir:match("([^/]+)$")
	local temp_install_dir = config.TEMP_INSTALL_PATH .. "/" .. package_name
	if args then
		local modified_args = {}
		for i, arg in ipairs(args) do
			if arg:match("^-t") then
				modified_args[i] = "-t " .. temp_install_dir
			elseif arg:match("^--target-directory=") then
				modified_args[i] = "--target-directory=" .. temp_install_dir
			else
				modified_args[i] = arg
			end
		end
		for _, arg in ipairs(modified_args) do
			cmd = cmd .. " " .. arg
		end
	end

print("\27[7m-> " .. cmd .. "\27[0m")
	local ok, _, code = os.execute(cmd)
	if not ok or code ~= 0 then
		error("install failed")
	end
end

function builder.meson_wrapper(build_dir, args)
	local cmd = "cd " .. build_dir .. " && meson setup"
	if args then
		for _, arg in ipairs(args) do
			cmd = cmd .. " " .. arg
		end
	end
print("\27[7m-> " .. cmd .. "\27[0m")
	local ok, _, code = os.execute(cmd)
	if not ok or code ~= 0 then
		error("meson failed")
	end
end

function builder.cargo_wrapper(build_dir, make_opts, args)
	local cmd = "cd " .. build_dir .. " && cargo"
	if make_opts.jobs then
		cmd = cmd .. " -j" .. make_opts.jobs
	end
	if args then
		for _, arg in ipairs(args) do
			cmd = cmd .. " " .. arg
		end
	end
print("\27[7m-> " .. cmd .. "\27[0m")
	local ok, _, code = os.execute(cmd)
	if not ok or code ~= 0 then
		error("cargo failed")
	end
end

function builder.go_wrapper(build_dir, args)
	local cmd = "cd " .. build_dir .. " && go"
	if args then
		for _, arg in ipairs(args) do
			cmd = cmd .. " " .. arg
		end
	end
print("\27[7m-> " .. cmd .. "\27[0m")
	local ok, _, code = os.execute(cmd)
	if not ok or code ~= 0 then
		error("go failed")
	end
end

function builder.npm_wrapper(build_dir, args)
	local cmd = "cd " .. build_dir .. " && npm"
	if args then
		for _, arg in ipairs(args) do
			cmd = cmd .. " " .. arg
		end
	end
print("\27[7m-> " .. cmd .. "\27[0m")
	local ok, _, code = os.execute(cmd)
	if not ok or code ~= 0 then
		error("npm failed")
	end
end

function builder.mvn_wrapper(build_dir, args)
	local cmd = "cd " .. build_dir .. " && mvn"
	if args then
		for _, arg in ipairs(args) do
			cmd = cmd .. " " .. arg
		end
	end
print("\27[7m-> " .. cmd .. "\27[0m")
	local ok, _, code = os.execute(cmd)
	if not ok or code ~= 0 then
		error("mvn failed")
	end
end

function builder.gradle_wrapper(build_dir, args)
	local cmd = "cd " .. build_dir .. " && gradle"
	if args then
		for _, arg in ipairs(args) do
			cmd = cmd .. " " .. arg
		end
	end
print("\27[7m-> " .. cmd .. "\27[0m")
	local ok, _, code = os.execute(cmd)
	if not ok or code ~= 0 then
		error("gradle failed")
	end
end

function builder.scons_wrapper(build_dir, make_opts, args)
	local cmd = "cd " .. build_dir .. " && scons"
	if make_opts and make_opts.jobs then
		cmd = cmd .. " -j" .. make_opts.jobs
	end
	if args then
		for _, arg in ipairs(args) do
			cmd = cmd .. " " .. arg
		end
	end
print("\27[7m-> " .. cmd .. "\27[0m")
	local ok, _, code = os.execute(cmd)
	if not ok or code ~= 0 then
		error("scons failed")
	end
end

function builder.bazel_wrapper(build_dir, args)
	local cmd = "cd " .. build_dir .. " && bazel"
	if args then
		for _, arg in ipairs(args) do
			cmd = cmd .. " " .. arg
		end
	end
print("\27[7m-> " .. cmd .. "\27[0m")
	local ok, _, code = os.execute(cmd)
	if not ok or code ~= 0 then
		error("bazel failed")
	end
end

function builder.patch_wrapper(build_dir, patch_file, args)
	local cmd = "cd " .. build_dir .. " && patch"
	if args then
		for _, arg in ipairs(args) do
			cmd = cmd .. " " .. arg
		end
	end
	cmd = cmd .. " -i " .. patch_file
print("\27[7m-> " .. cmd .. "\27[0m")
	local ok, _, code = os.execute(cmd)
	if not ok or code ~= 0 then
		error("patch failed")
	end
end

function builder.git_clone_wrapper(build_dir,url, dest, args)
	local cmd = "cd " .. build_dir .. " && git clone"
	if args then
		for _, arg in ipairs(args) do
			cmd = cmd .. " " .. arg
		end
	end
	cmd = cmd .. " " .. url .. " " .. dest
print("\27[7m-> " .. cmd .. "\27[0m")
	local ok, _, code = os.execute(cmd)
	if not ok or code ~= 0 then
		error("git clone failed")
	end
end

function builder.git_wrapper(build_dir, args)
	local cmd = "cd " .. build_dir .. " && git"
	if args then
		for _, arg in ipairs(args) do
			cmd = cmd .. " " .. arg
		end
	end
print("\27[7m-> " .. cmd .. "\27[0m")
	local ok, _, code = os.execute(cmd)
	if not ok or code ~= 0 then
		error("git failed")
	end
end

function builder.wget_wrapper(build_dir,url, dest, args)
	local cmd = "cd " .. build_dir .. " && wget"
	if args then
		for _, arg in ipairs(args) do
			cmd = cmd .. " " .. arg
		end
	end
	cmd = cmd .. " " .. url
	if dest then
		cmd = cmd .. " -O " .. dest
	end
print("\27[7m-> " .. cmd .. "\27[0m")
	local ok, _, code = os.execute(cmd)
	if not ok or code ~= 0 then
		error("wget failed")
	end
end

function builder.curl_wrapper(build_dir,url, dest, args)
	local cmd = "cd " .. build_dir .. " && curl"
	if args then
		for _, arg in ipairs(args) do
			cmd = cmd .. " " .. arg
		end
	end
	if dest then
		cmd = cmd .. " -o " .. dest
	else
		cmd = cmd .. " -fsSL"
	end
	cmd = cmd .. " " .. url
print("\27[7m-> " .. cmd .. "\27[0m")
	local ok, _, code = os.execute(cmd)
	if not ok or code ~= 0 then
		error("curl failed")
	end
end

function builder.tar_wrapper(build_dir,archive, dest, args)
	local cmd = "cd " .. build_dir .. " && tar"
	if args then
		for _, arg in ipairs(args) do
			cmd = cmd .. " " .. arg
		end
	else
		cmd = cmd .. " -xf"
	end
	cmd = cmd .. " " .. archive
	if dest then
		cmd = cmd .. " -C " .. dest
	end
print("\27[7m-> " .. cmd .. "\27[0m")
	local ok, _, code = os.execute(cmd)
	if not ok or code ~= 0 then
		error("tar failed")
	end
end

function builder.unzip_wrapper(build_dir,archive, dest, args)
	local cmd = "cd " .. build_dir .. " && unzip"
	if args then
		for _, arg in ipairs(args) do
			cmd = cmd .. " " .. arg
		end
	else
		cmd = cmd .. " -q"
	end
	cmd = cmd .. " " .. archive
	if dest then
		cmd = cmd .. " -d " .. dest
	end
print("\27[7m-> " .. cmd .. "\27[0m")
	local ok, _, code = os.execute(cmd)
	if not ok or code ~= 0 then
		error("unzip failed")
	end
end

function builder.python_wrapper(build_dir, args)
	local cmd = "cd " .. build_dir .. " && python"
	if args then
		for _, arg in ipairs(args) do
			cmd = cmd .. " " .. arg
		end
	end
print("\27[7m-> " .. cmd .. "\27[0m")
	local ok, _, code = os.execute(cmd)
	if not ok or code ~= 0 then
		error("python failed")
	end
end

function builder.setuid_wrapper(build_dir,file, owner, mode)
	local cmd
	if owner then
		cmd = "cd " .. build_dir .. " && chown " .. owner .. " " .. file
		print("\27[7m-> " .. cmd .. "\27[0m")
		local ok, _, code = os.execute(cmd)
		if not ok or code ~= 0 then
			error("chown failed")
		end
	end
	if mode then
		cmd = "cd " .. build_dir .. " && chmod " .. mode .. " " .. file
		print("\27[7m-> " .. cmd .. "\27[0m")
		local ok, _, code = os.execute(cmd)
		if not ok or code ~= 0 then
			error("chmod failed")
		end
	end
end

return builder
