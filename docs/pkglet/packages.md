# Package Manifests
Package Manifests are `.lua` files which describe information about the package, as well as building and installation steps.

## Location
They are typically stored in Pkglet [repositories](/pkglet/repos), usually using `git`.

## Example Manifest 
```lua
pkg = {
    name = "org.example.package",
    version = "1.0.0",
    description = "Example package",
    maintainer = "You <you@example.com>",
    license = "MIT",
    homepage = "https://example.com",
    depends = {
        "org.deps.foo>=1.0.0",
        { name = "org.deps.bar", constraint = "^2.0.0" }
    },
    build_depends = {
        "org.build.meson>=0.50.0"
    },
    optional_depends = {
        "org.crypto.openssl>=1.1.0",
        "org.compression.zlib>=1.2.0"
    },
    conflicts = { "org.package.conflicting" },
    replaces = { "org.package.legacy" },
    provides = { "virtual-service" },
    conflicts = {},
    provides = { "example" },
    sources = {
        binary = {
            type = "tar",
            url = "https://example.com/package-1.0.0.tar.gz"
        },
        source = {
            type = "git",
            url = "https://github.com/example/package",
            commit = "v1.0.0"
        }
    },
    options = {
        feature_x = {
            type = "boolean",
            default = false,
            description = "Enable feature X"
        },
        config = {
			type = "string",
			default = "",
			description = "extra configuration options to pass to ./configure",
		},
		static = {
			type = "boolean",
			default = true,
			description = "enables compiling statically",
		},
    },
}
function pkg.source()
	return function(hook)
		hook("prepare")(function()
			local configure_opts = { "--prefix=/usr" }
			if OPTIONS.static then
				table.insert(configure_opts, "--enable-static")
			end
			configure(configure_opts)
		end)

		hook("build")(function()
			make()
		end)

		hook("install")(function()
			make({}, false)
		end)
	end
end

function pkg.binary()
	return function(hook)
		hook("install")(function()
			install({ "*", INSTALL }, "cp -r")
		end)
	end
end
```

## Pkglet-provided variables
Pkglet provides some variables to the package's environment. They include:

### `OPTIONS`
This is a Lua table that contains the user-provided options (or their defaults if not passed). or an empty table.

### `INSTALL`
This is a string pointing to the temp install path created by Pkglet, this is path is meant to be used instead of `/` when installing.

### `ARCH`
This is a string having the user's CPU architecture. Could potentially be used in the future for cross-compiling. Not yet though.

### `ROOT`
This is a string pointing to either `/` or to the bootstrap directory.

### `CONFIG`
This is a Lua table pointing to the `config.lua` (Pkglet source code).

### `pkglet`
This is a Lua table with multiple functions pointing to Pkglet's internal work.
- `install(name, options)`: Request user (unless `--noask` is passed) to install a package with `options`.
- `uninstall(name, options)`: Request user (unless `--noask` is passed) to uninstall a package. `options` only has `noask` support.
- `sync()`: Sync repositories.
- `info(name)`: Query package information.

## Pkglet-provided functions
Pkglet provides a lot of functions to the package's environment to help in reducing boilerplate. They include:

### `exec(command)`
This is a wrapper to `os.execute` that does a `cd` to `INSTALL` before executing the command.
- `command` (string): Command to execute.

### `make(extra_args, is_build, destvar, prefix)`
This is a wrapper to the `make` utility.
- `extra_args` (table): These are for extra stuff to pass to `make`. like `clean` or other commands.
- `is_build` (boolean, default: `true`): This boolean determines if `pkglet` should automatically do the `install` command with `destvar` set.
- `destvar` (boolean, default: `DESTDIR`): explained above.
- `prefix` (string): What to run right before `make` command, useful if you want to override stuff.

### `cmake(args)`
This is a wrapper to the `cmake` build system.
- `args` (table): extra arguments to pass to `cmake`

### `configure(args, name)`
This is a wrapper to the GNU autoconf's `./configure` utility.
- `args` (table): extra arguments to pass to `./configure`
- `name` (string): name of `./configure`. Example: `Configure`.

### AND MORE BUT IM LAZY RIGHT NOW.
