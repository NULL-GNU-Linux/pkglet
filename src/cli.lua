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
        noask = false,
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
        elseif arg == "--noask" then
            parsed.noask = true
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
    print("\27[1;32mpkglet\27[0m - The hybrid package manager for NULL\n" ..
"\n" ..
"USAGE:\n" ..
    "\27[1;32mpkglet\27[0m \27[1;37m<command> [options] [package]\27[0m\n" ..
"\n" ..
"COMMANDS:\n" ..
"   \27[1;37mi/install <package>\27[0m        Install a package\n" ..
"   \27[1;37mu/uninstall <package>\27[0m      Uninstall a package\n" ..
"   \27[1;37ms/search <query>\27[0m           Search for packages\n" ..
"   \27[1;37mS/sync\27[0m                     Sync package repositories\n" ..
"   \27[1;37mI/info <package>\27[0m           Show package information\n" ..
"\n" ..
"OPTIONS:\n" ..
"   \27[1;37m--source\27[0m                   Build from source\n" ..
"   \27[1;37m--binary\27[0m                   Install binary package\n" ..
"   \27[1;37m--bootstrap-to=<path>\27[0m      Bootstrap to alternate root\n" ..
"   \27[1;37m--noask\27[0m                    Skip installation confirmation\n" ..
"   \27[1;37m--<option>=<value>\27[0m         Set package option\n" ..
"   \27[1;37m--<flag>\27[0m                   Enable boolean package option\n" ..
"\n" ..
"EXAMPLES:\n" ..
"   pkglet i org.kernel.linux\n" ..
"   pkglet install org.kernel.linux --source --menuconfig\n" ..
"   pkglet install gcc --bootstrap-to=/mnt/bootstrap\n" ..
"   pkglet uninstall org.kernel.linux\n" ..
"   pkglet uninstall org.kernel.linux --noask\n" ..
"   pkglet S\n" ..
"   pkglet s git\n" ..
"\n" ..
"LICENSE: \27[1;30mMIT\27[0m\n")
end

return cli
