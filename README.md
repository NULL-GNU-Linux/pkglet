# `pkglet`

A Lua-based hybrid package manager for the NULL GNU/Linux distribution.

## Features

- **Hybrid Build System**: Supports both binary and source packages
- **Lua Manifests**: Packages are defined as executable Lua scripts
- **Dependency Resolution**: Automatic dependency handling
- **Option Tables**: Per-package build options (like Portage USE flags)
- **Package Masking**: Prevent installation of specific packages
- **Bootstrap Mode**: Install packages to alternate root directories
- **Modular Architecture**: Each module serves one purpose
- **Build Tool Integration**: Helpers for make, cmake, ninja, configure

## Documentation

Generate documentation:
```
make docs
```

Install documentation:
```
make install_docs
```

## Installation

```bash
make install
```

Default installation:
- Binary: `/usr/bin/pkglet`
- Modules: `/usr/lib/pkglet/*.lua`
- Config: `/etc/pkglet/`

## Configuration

### Repository Configuration

Edit `/etc/pkglet/repos.conf`:

```
[repositories]
main /var/db/pkglet/repos/main 100
overlay /var/db/pkglet/repos/overlay 50
testing /var/db/pkglet/repos/testing 10

[mirrors]
main https://mirror1.example.com/repos/main https://mirror2.example.com/repos/main
overlay https://mirror1.example.com/repos/overlay
```

### Build Options

Edit `/etc/pkglet/make.lua`:

```lua
MAKEOPTS = {
    jobs = 8,
    load = 9,
}
```

### Package Options

Edit `/etc/pkglet/package.opts/<package-name>`:

```
org.kernel.linux menuconfig no_modules
```

### Package Masking

Edit `/etc/pkglet/package.mask`:

```
org.kernel.linux
bad.package.foo
```

### Package Pinning/Locking

Edit `/etc/pkglet/package.lock`:

```
org.kernel.linux 6.17.5
org.gnu.gcc 11.2.0
```

## Usage

### Install Package

```bash
pkglet i org.kernel.linux
pkglet i org.kernel.linux --source
pkglet i org.kernel.linux --menuconfig
pkglet i org.kernel.linux --with-optional
pkglet i org.kernel.linux --to 6.17.5
```

**Optional Dependencies:**
Use `--with-optional` to install optional dependencies that enhance functionality but aren't required for core operation.

### Upgrade Package

```bash
pkglet U org.kernel.linux
pkglet upgrade org.kernel.linux --pin
```

### Downgrade Package

```bash
pkglet d org.kernel.linux --to 6.15.0
pkglet downgrade org.kernel.linux --to v6.15.0
pkglet d org.kernel.linux --to a1b2c3d4
pkglet downgrade org.kernel.linux --to 6.15.0 --pin
```

### List Package Versions

```bash
pkglet L org.kernel.linux
pkglet list-versions org.kernel.linux
```

### Pin/Unpin Packages

```bash
pkglet pin org.kernel.linux 6.17.5
pkglet pin org.kernel.linux
pkglet unpin org.kernel.linux
```

### Uninstall Package

```bash
pkglet u org.kernel.linux
```

### Reverse Dependencies

```bash
pkglet R org.kernel.linux
pkglet reverse-deps org.kernel.linux
```

### Force Installation

```bash
pkglet i org.kernel.linux --force
pkglet install org.kernel.linux --force
```

### GPG Operations

```bash
pkglet G list-keys                          # List all keys
pkglet G import-key /path/to/key.pub          # Import key from file
pkglet G import-key-server KEYID               # Import key from server
pkglet G generate-key "Name" email@example.com  # Generate new key pair
pkglet G export-key KEYID [output-file]       # Export public key
pkglet G sign-package package.tar.gz [key-id]   # Sign package file
pkglet G verify-package package.tar.gz.asc [sig-file] # Verify signature
pkglet G delete-key KEYID                      # Delete key
```

### Search Packages

```bash
pkglet s linux
```

### Package Information

```bash
pkglet I org.kernel.linux
```

### Sync Repositories

```bash
pkglet S
```

### Bootstrap Mode

Install to alternate root (useful for cross-compilation or system bootstrapping):

```bash
pkglet I gcc --bootstrap-to /mnt/bootstrap
```

All files will be installed to `/mnt/bootstrap` instead of `/`.

## Package Manifest Format

Package manifests are Lua files that define package metadata and build instructions.

### Basic Structure

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
    },
}
```

### Build Functions

#### Source Build

```lua
function pkg.source()
    return function(hook)
        hook("prepare")(function()
            -- Preparation steps
        end)
        
        hook("build")(function()
            configure({"--prefix=/usr"})
            make()
        end)
        
        hook("install")(function()
            make({"install"})
        end)
        
        hook("post_install")(function()
            -- Post-install steps
        end)
    end
end
```

#### Binary Install

```lua
function pkg.binary()
    return function(hook)
        hook("pre_install")(function()
            -- Pre-install steps
        end)
        
        hook("install")(function()
            -- Installation handled by pkglet
        end)
        
        hook("post_install")(function()
            -- Post-install steps
        end)
    end
end
```

#### Uninstall

```lua
function pkg.uninstall()
    return function(hook)
        hook("pre_uninstall")(function()
            -- Cleanup before uninstall
        end)
        
        hook("post_uninstall")(function()
            -- Cleanup after uninstall
        end)
    end
end
```

### Build Helpers

Available in hook functions:

- `make(args, is_build, destvar)` - Run make with configured options.
- `cmake(args)` - Run cmake
- `configure(args)` - Run ./configure
- `ninja(args)` - Run ninja with configured options
- `exec(command)` - An alias to Lua's `os.execute`
- `OPTIONS` - Table of enabled package options

### Source Types

- `tar`: Downloads and extracts tar archives (gz, bz2, xz, zip)
- `git`: Clones git repositories
- `file`: Downloads single files

### Dependencies

#### Version Constraints

Dependencies support semantic versioning constraints:

```lua
depends = {
    "org.package.name>=1.0.0",        -- Minimum version
    "org.package.name<=2.0.0",        -- Maximum version
    "org.package.name==1.5.0",        -- Exact version
    "org.package.name!=1.0.0",        -- Exclude version
    "org.package.name^1.0.0",         -- Caret range (>=1.0.0 <2.0.0)
    "org.package.name~1.5.0",         -- Tilde range (>=1.5.0 <1.6.0)
    { name = "org.package.name", constraint = ">=2.0.0" }
}
```

#### Build Dependencies

Build-time dependencies are only required during compilation:

```lua
build_depends = {
    "org.build.meson>=0.50.0",
    "org.build.ninja"
}
```

#### Optional Dependencies

Optional dependencies enhance functionality but are not required:

```lua
optional_depends = {
    "org.openssl.libssl>=1.1.0",
    { name = "net.zlib", constraint = ">=1.2.0" },
}
```

## Architecture

### Modules

Each module serves a single purpose:

- `cli.lua` - Command-line argument parsing
- `config.lua` - Configuration and settings management
- `loader.lua` - Package manifest loading and validation
- `resolver.lua` - Dependency resolution
- `fetcher.lua` - Source downloading and extraction
- `builder.lua` - Build process orchestration
- `installer.lua` - Installation and uninstallation
- `search.lua` - Package searching
- `sync.lua` - Repository synchronization
- `version.lua` - Version comparison and sorting

### File Locations

- Installed packages database: `/var/lib/pkglet/`
- Build cache: `~/.cache/pkglet/build/`
- Downloaded sources: `~/.cache/pkglet/distfiles/`

## License

`pkglet` is licensed under [the MIT License](LICENSE).
