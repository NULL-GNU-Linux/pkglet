--- Command line interface module for parsing and handling user input
--
-- This module provides comprehensive command line parsing capabilities for the pkglet
-- package manager. It handles all supported commands, options, and arguments, converting
-- raw command line input into a structured format that the rest of the application
-- can process. The parser supports various flag formats, package options, and special
-- modes like bootstrap installation. It's designed to be robust and user-friendly,
-- providing clear parsing for complex command structures while maintaining compatibility
-- with common package manager interface patterns.
-- @module cli

local cli = {}

--- Parse command line arguments into structured command data
--
-- This function processes raw command line arguments and converts them into a
-- structured table containing commands, packages, options, and parameters. It handles
-- various argument formats including flags, key-value pairs, and positional arguments.
-- The parser supports build type selection (--source, --binary), bootstrap targets,
-- and arbitrary package-specific options that get passed through to the build system.
--
-- The function follows a specific parsing order: command first, then package name,
-- then query/extra arguments, with options being processed as they appear.
-- This predictable behavior ensures consistent command interpretation.
--
-- @param args table Raw command line arguments array (usually from arg table)
-- @return table Structured command data containing fields: command, package, query,
--               build_from, options, and bootstrap_to
function cli.parse(args)
    local parsed = {
        command = nil,
        package = nil,
        query = nil,
        build_from = "auto",
        options = {},
        bootstrap_to = nil,
    }

    if #args == 0 then
        return parsed
    end

    parsed.command = args[1]
    local i = 2
    while i <= #args do
        local arg = args[i]
        if arg == "--source" then
            parsed.build_from = "source"
        elseif arg == "--binary" then
            parsed.build_from = "binary"
        elseif arg == "--bootstrap-to" then
            i = i + 1
            parsed.bootstrap_to = args[i]
        elseif arg:match("^%-%-") then
            local opt = arg:sub(3)
            local key, value = opt:match("^([^=]+)=(.+)$")
            if key then
                parsed.options[key] = value
            else
                parsed.options[opt] = true
            end
        else
            if not parsed.package then
                parsed.package = arg
            else
                parsed.query = arg
            end
        end

        i = i + 1
    end

    return parsed
end

--- Display comprehensive help information to the user
--
-- This function prints detailed usage instructions covering all available commands,
-- supported options, and practical examples. The help output is formatted for
-- readability and includes descriptions of installation commands, search operations,
-- repository synchronization, and package information queries. It also documents
-- various option formats including build type selection, bootstrap targets,
-- and package-specific configuration options.
--
-- The help system is designed to be self-contained and comprehensive, allowing
-- users to understand the full capabilities of pkglet without needing external
-- documentation. Examples show common usage patterns and advanced features.
function cli.print_help()
    print([[
pkglet - The hybrid package manager for NULL

USAGE:
    pkglet <command> [options] [package]

COMMANDS:
    i <package>      Install a package
    u <package>      Uninstall a package
    s <query>        Search for packages
    S                Sync package repositories
    I <package>      Show package information

OPTIONS:
    --source               Build from source
    --binary               Install binary package
    --bootstrap-to=<path>  Bootstrap to alternate root
    --<option>=<value>     Set package option
    --<flag>               Enable boolean package option

EXAMPLES:
    pkglet i org.kernel.linux
    pkglet i org.kernel.linux --source --menuconfig
    pkglet i gcc --bootstrap-to=/mnt/bootstrap
    pkglet u org.kernel.linux

LICENSE: MIT
]])
end

return cli
