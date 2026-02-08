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
main /var/db/pkglet/repos/main
overlay /var/db/pkglet/repos/overlay
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

## Usage

### Install Package

```bash
pkglet i org.kernel.linux
pkglet i org.kernel.linux --source
pkglet i org.kernel.linux --menuconfig
```

### Uninstall Package

```bash
pkglet u org.kernel.linux
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
    depends = { "org.deps.foo", "org.deps.bar" },
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

- `make(args, is_build)` - Run make with configured options
- `cmake(args)` - Run cmake
- `configure(args)` - Run ./configure
- `ninja(args)` - Run ninja with configured options
- `OPTIONS` - Table of enabled package options

### Source Types

- `tar`: Downloads and extracts tar archives (gz, bz2, xz, zip)
- `git`: Clones git repositories
- `file`: Downloads single files

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

### File Locations

- Installed packages database: `/var/lib/pkglet/`
- Build cache: `~/.cache/pkglet/build/`
- Downloaded sources: `~/.cache/pkglet/distfiles/`

## License

`pkglet` is licensed under [the MIT License](LICENSE).
