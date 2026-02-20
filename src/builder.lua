--- Package building module with support for multiple build systems
--
-- This module provides comprehensive package building capabilities supporting
-- various build systems including make, cmake, ninja, and configure scripts.
-- It orchestrates the entire build process from source preparation through
-- compilation and installation, handling different build types (source vs binary)
-- and managing build environments. The module includes wrapper functions for
-- common build tools and supports parallel builds with configurable job limits.
--
-- The build system is designed to be flexible and extensible, allowing packages
-- to define custom build procedures while providing standardized interfaces for
-- common operations. Build environments are sandboxed to prevent contamination
-- between different packages and build configurations.
-- @module builder

local builder = {}
local config = require("src.config")

--- Execute the complete build process for a package
--
-- This function orchestrates the entire package build process, setting up the
-- build environment, executing the appropriate build function, and managing
-- build hooks. It supports both source builds (compiling from source code)
-- and binary builds (installing pre-compiled packages). The function creates
-- a secure build environment with access to wrapper functions for common build
-- tools and handles both successful builds and error conditions gracefully.
--
-- The build process includes multiple phases: preparation, building, pre-install,
-- installation, and post-install operations. Each phase can be customized by
-- the package manifest through hooks, allowing for complex build scenarios
-- while maintaining a consistent interface.
--
-- @param manifest table Complete package manifest containing build instructions,
--                       dependencies, and metadata for the package being built
-- @param build_dir string Absolute path to the temporary build directory where
--                        source code will be extracted and compilation will occur
-- @param build_type string Type of build to perform: "source" for compiling from
--                          source code, "binary" for installing pre-compiled packages
-- @param options table Optional build options that can modify build behavior,
--                     enable/disable features, or pass parameters to the build system

function builder.build(manifest, build_dir, build_type, options)
	local make_opts = config.get_make_opts()
	local env = manifest._env
	env.OPTIONS = options or {}
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
	env.exec = os.execute
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

--- Execute make commands with parallel build support and installation handling
--
-- This function provides a comprehensive wrapper around GNU make, implementing
-- parallel compilation with configurable job limits and load average monitoring
-- to prevent system overload. It automatically detects whether to perform a build
-- operation or installation based on the is_build parameter, with installation
-- automatically redirecting to the configured root directory. The wrapper
-- integrates with pkglet's build configuration system to apply user-defined
-- make options and supports additional arguments for complex build scenarios.
--
-- The function is essential for managing system resources during builds while
-- providing the flexibility needed for different package requirements and
-- ensuring proper installation paths are respected during package deployment.
--
-- @param build_dir string Absolute path to the directory where make command should be executed
-- @param make_opts table Configuration options containing: jobs (parallel build limit),
-- load (system load threshold), and extra (additional make flags)
-- @param extra_args table Optional array of additional arguments passed directly to make command
-- @param is_build boolean True for compilation with parallel jobs, false for installation mode
-- @param destvar string Variable name for destination directory (for `make install`) (default: DESTDIR)
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

--- Execute CMake configuration commands with flexible argument support
--
-- This function provides a wrapper for the CMake build system generator,
-- enabling packages to configure their build environment using CMake's
-- declarative configuration approach. The wrapper supports passing custom
-- arguments to control build types, installation paths, feature toggles,
-- and other CMake-specific options. It's designed for projects that use
-- CMake's cross-platform build system generation capabilities.
--
-- The function handles the initial configuration phase of CMake-based builds,
-- typically used before invoking make or ninja for actual compilation.
-- It integrates seamlessly with pkglet's build environment while providing
-- the flexibility needed for complex CMake configurations.
--
-- @param build_dir string Absolute path to the source directory containing CMakeLists.txt
-- @param args table Optional array of CMake arguments such as build type, installation prefix,
--                  feature flags, and other CMake configuration options
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

--- Execute GNU autotools configure scripts with comprehensive option support
--
-- This function provides a wrapper for traditional GNU autotools configure scripts,
-- which are commonly used in open-source projects for cross-platform build
-- configuration. The wrapper handles the environment setup and execution of
-- configure scripts that detect system capabilities, set build parameters,
-- and generate the appropriate Makefiles for compilation. It supports passing
-- custom arguments for prefix paths, feature selection, dependency paths,
-- and other configure-specific options.
--
-- The function is essential for building traditional Unix-style packages that
-- rely on the autoconf/automake build system, providing a standardized
-- interface while maintaining flexibility for complex configuration scenarios.
--
-- @param build_dir string Absolute path to the source directory containing configure script
-- @param args table Optional array of configure script arguments including installation prefix,
--                  feature flags, library paths, and other autotools configuration options
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

--- Execute Ninja build commands with high-performance parallel compilation
--
-- This function provides a wrapper for the Ninja build system, which is designed
-- for fast incremental builds and is commonly used by CMake-generated projects
-- and other modern build systems. Ninja excels at parallel execution and minimal
-- rebuild overhead, making it ideal for large projects and continuous integration
-- environments. The wrapper integrates with pkglet's parallel build configuration
-- to respect job limits and load average thresholds while maximizing build speed.
--
-- The function is particularly useful for projects that generate Ninja build
-- files, offering superior performance over traditional make for incremental
-- builds while maintaining compatibility with pkglet's resource management.
--
-- @param build_dir string Absolute path to the directory containing build.ninja file
-- @param make_opts table Configuration for parallel execution including jobs limit
--                      and load average threshold to prevent system overload
-- @param args table Optional array of additional ninja arguments for specific targets
--                  or special build modes like clean or verbose output

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

--- Execute install commands with temporary installation path
--
-- This function provides a wrapper for the GNU coreutils install command,
-- ensuring that files are installed to the temporary installation directory
-- first before being copied to the final destination. This allows for proper
-- file tracking and conflict resolution during package installation.
--
-- @param build_dir string Absolute path to the directory where install command should be executed
-- @param args table Optional array of additional arguments passed directly to install command
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

--- Execute Meson configuration commands with flexible argument support
--
-- This function provides a wrapper for the Meson build system, which is
-- designed for fast and user-friendly configuration of projects. It supports
-- passing custom arguments for build types, installation paths, feature toggles,
-- and other Meson-specific options.
--
-- @param build_dir string Absolute path to the source directory containing meson.build
-- @param args table Optional array of Meson arguments such as build type, installation prefix,
--                  feature flags, and other Meson configuration options
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
--- Execute Cargo build commands for Rust projects
--
-- This function provides a wrapper for Cargo, Rust's package manager and build tool.
-- It supports building, testing, and installing Rust crates with parallel compilation.
--
-- @param build_dir string Absolute path to the Cargo project directory
-- @param make_opts table Configuration for parallel execution including jobs limit
-- @param args table Optional array of Cargo arguments such as "build", "test", "install", "--release"
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

--- Execute Go build commands
--
-- This function provides a wrapper for the Go programming language build tool.
-- It supports building Go packages and installing binaries.
--
-- @param build_dir string Absolute path to the Go project directory
-- @param args table Optional array of go arguments such as "build", "install", "-o", tags
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

--- Execute npm commands for Node.js packages
--
-- This function provides a wrapper for npm, Node.js package manager.
-- It supports installing dependencies, running scripts, and building Node.js projects.
--
-- @param build_dir string Absolute path to the Node.js project directory
-- @param args table Optional array of npm arguments such as "install", "run build", "--production"
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

--- Execute Maven build commands for Java projects
--
-- This function provides a wrapper for Maven, a build automation tool for Java projects.
-- It supports compiling, testing, and packaging Java applications.
--
-- @param build_dir string Absolute path to the Maven project directory
-- @param args table Optional array of mvn arguments such as "compile", "package", "-DskipTests"
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

--- Execute Gradle build commands for Java/Android projects
--
-- This function provides a wrapper for Gradle, a build automation tool
-- used for Java, Android, and other JVM-based projects.
--
-- @param build_dir string Absolute path to the Gradle project directory
-- @param args table Optional array of gradle arguments such as "build", "assemble", "test"
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

--- Execute SCons build commands
--
-- This function provides a wrapper for SCons, a Python-based build tool.
-- It supports building software projects using SConstruct files.
--
-- @param build_dir string Absolute path to the SCons project directory
-- @param args table Optional array of scons arguments such as "-j" for parallel, "install"
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

--- Execute Bazel build commands
--
-- This function provides a wrapper for Bazel, a build and test tool
-- developed by Google. It supports building and testing a wide variety of languages.
--
-- @param build_dir string Absolute path to the Bazel project directory
-- @param args table Optional array of bazel arguments such as "build", "test", "//target"
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

--- Apply patches to source files
--
-- This function provides a wrapper for the patch command, enabling
-- application of diff/patch files to source code.
--
-- @param build_dir string Absolute path to the directory where patch should be applied
-- @param patch_file string Path to the patch file
-- @param args table Optional array of patch arguments such as "-p1", "-i"
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

--- Clone git repositories
--
-- This function provides a wrapper for git clone, enabling repository cloning.
--
-- @param url string Git repository URL to clone
-- @param dest string Destination directory for the cloned repository
-- @param args table Optional array of git arguments such as "--depth", "--branch"
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

--- Execute arbitrary git commands
--
-- This function provides a wrapper for git operations like checkout, pull, etc.
--
-- @param build_dir string Absolute path to the git repository directory
-- @param args table Array of git arguments such as "checkout", "pull", "submodule", "update"
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

--- Download files using wget
--
-- This function provides a wrapper for wget, enabling file downloads.
--
-- @param url string URL to download
-- @param dest string Destination file path (optional)
-- @param args table Optional array of wget arguments such as "-q", "-O", "--no-check-certificate"
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

--- Download files using curl
--
-- This function provides a wrapper for curl, enabling file downloads and HTTP requests.
--
-- @param url string URL to download
-- @param dest string Destination file path (optional)
-- @param args table Optional array of curl arguments such as "-fsSL", "-o"
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

--- Extract tar archives
--
-- This function provides a wrapper for tar, enabling extraction of tar, tar.gz, tar.bz2, tar.xz archives.
--
-- @param archive string Path to the archive file
-- @param dest string Destination directory for extraction (optional)
-- @param args table Optional array of tar arguments
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

--- Extract zip archives
--
-- This function provides a wrapper for unzip, enabling extraction of zip archives.
--
-- @param archive string Path to the zip file
-- @param dest string Destination directory for extraction (optional)
-- @param args table Optional array of unzip arguments such as "-q" for quiet
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

--- Run Python scripts or modules
--
-- This function provides a wrapper for running Python scripts and modules.
--
-- @param build_dir string Absolute path where python should be executed
-- @param args table Array of Python arguments such as "setup.py", "build", "install"
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

--- Set file ownership and permissions (setuid/setgid)
--
-- This function provides a wrapper for chown and chmod to set file ownership
-- and special permissions like setuid/setgid.
--
-- @param file string Path to the file or directory
-- @param owner string Owner in "user:group" format (optional, nil for chmod only)
-- @param mode string Permission mode (e.g., "4755" for setuid+rwx)
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
