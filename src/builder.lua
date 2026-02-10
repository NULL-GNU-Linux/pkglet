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
	env.make = function(extra_args, is_build, destvar)
		return builder.make_wrapper(build_dir, make_opts, extra_args, is_build, destvar)
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
	env.install = function(args)
		return builder.install_wrapper(build_dir, args)
	end
	env.meson = function(args)
		return builder.meson_wrapper(build_dir, args)
	end
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
function builder.make_wrapper(build_dir, make_opts, extra_args, is_build, destvar)
    destvar = destvar or "DESTDIR"
	local cmd = "cd " .. build_dir .. " && make"
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
function builder.install_wrapper(build_dir, args)
	local cmd = "cd " .. build_dir .. " && install"
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

return builder
