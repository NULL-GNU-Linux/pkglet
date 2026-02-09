--- Example package manifest demonstrating comprehensive kernel package configuration
--
-- This manifest serves as a complete example of how to structure package definitions
-- in the pkglet system, showcasing all major features including dual source/binary
-- support, build options, dependency management, and custom build procedures. The
-- manifest demonstrates best practices for package naming, versioning, metadata
-- completeness, and build system integration. It illustrates how to handle complex
-- packages like the Linux kernel that require extensive configuration options,
-- multiple build phases, and specialized installation procedures.
--
-- The example shows proper use of dot notation for hierarchical naming, comprehensive
-- metadata for package discovery, flexible source specification supporting both
-- development and release workflows, and advanced build options for user customization.
-- This manifest can serve as a template for other complex system packages.
-- @module example-manifest

pkg = {
	name = "org.kernel.linux",
	version = "6.17.5",
	description = "The Linux Kernel",
	maintainer = "NEOAPPS <neo@obsidianos.xyz>",
	license = "GPL-2.0",
	homepage = "https://kernel.org",
	depends = { 
		"org.gnu.gcc>=9.0.0",
		{ name = "org.gnu.make", constraint = ">=4.0.0" },
		"org.libc.glibc"
	},
	build_depends = {
		"org.libc.linux-headers>=5.0.0",
		{ name = "org.util.bc", constraint = ">=1.0.0" }
	},
	conflicts = {},
	provides = { "linux" },
	sources = {
		binary = {
			type = "tar",
			url = "https://example.com/something.tar.gz"
		},
		source = {
			type = "git",
			url = "https://github.com/torvalds/linux",
			commit = "master"
		}
	},
	options = {
		menuconfig = {
			type = "boolean",
			default = false
		},
		no_modules = {
			type = "boolean",
			default = false,
			description = "disables compiling modules"
		},
	},
}

function pkg.source()
	return function(hook)
		hook("prepare")(function()
			print("Preparing kernel build...")
		end)

		hook("build")(function()
			make({"defconfig"}, false)
			make()
		end)

		hook("pre_install")(function()
			print("Pre-install steps...")
		end)

		hook("install")(function()
			make({}, false)
			if not OPTIONS.no_modules then
				make({"modules_install"}, false)
			end
		end)

		hook("post_install")(function()
			print("Kernel installed successfully")
		end)
	end
end

function pkg.binary()
	tmpdir = os.getenv("HOME") .. "/.cache/pkglet/build/" .. pkg.name
	return function(hook)
		hook("pre_install")(function()
			print("Preparing binary installation...")
		end)

		hook("install")(function()
			print("Installing binary package...")
		end)

		hook("post_install")(function()
			print("Binary package installed")
		end)
	end
end

function pkg.uninstall()
	return function(hook)
		hook("pre_uninstall")(function()
			print("Pre-uninstall cleanup...")
		end)

		hook("post_uninstall")(function()
			print("Kernel uninstalled")
		end)
	end
end
