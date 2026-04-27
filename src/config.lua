local config = {}
local function is_root()
    return os.execute("id -u 2>/dev/null | grep -q '^0$'") == true
end

local function get_home()
    return os.getenv("HOME") or "/root"
end

local function setup_non_root_paths()
    local home = get_home()
    local local_base = home .. "/.local"
    config.PREFIX = local_base
    config.ROOT = local_base .. "/"
    config.BIN_PATH = local_base .. "/bin"
    config.LIB_PATH = local_base .. "/lib"
    config.LIB64_PATH = local_base .. "/lib64"
    config.SHARE_PATH = local_base .. "/share"
    config.DB_PATH = local_base .. "/var/lib/pkglet"
    config.CACHE_PATH = home .. "/.cache/pkglet"
    config.BUILD_PATH = config.CACHE_PATH .. "/build"
    config.TEMP_INSTALL_PATH = config.CACHE_PATH .. "/temp_install"
    config.DISTFILES_PATH = config.CACHE_PATH .. "/distfiles"
    config.CONFIG_DIR = home .. "/.config/pkglet"
    config.REPOS_CONF = config.CONFIG_DIR .. "/repos.conf"
    config.MAKE_CONF = config.CONFIG_DIR .. "/make.lua"
    config.PACKAGE_OPTS = config.CONFIG_DIR .. "/package.opts"
    config.PACKAGE_MASK = config.CONFIG_DIR .. "/package.mask"
    config.PACKAGE_LOCK = config.CONFIG_DIR .. "/package.lock"
end

if not is_root() then
    setup_non_root_paths()
else
    local prefix = os.getenv("PKGLET_PREFIX") or ""
    config.PREFIX = prefix
    config.ROOT = prefix .. "/"
    if prefix == "/usr/local" or prefix == "" then
        config.BIN_PATH = "/usr/local/bin"
        config.LIB_PATH = "/usr/local/lib"
        config.LIB64_PATH = "/usr/local/lib64"
        config.SHARE_PATH = "/usr/local/share"
    else
        config.BIN_PATH = prefix .. "/bin"
        config.LIB_PATH = prefix .. "/lib"
        config.LIB64_PATH = prefix .. "/lib64"
        config.SHARE_PATH = prefix .. "/share"
    end
    config.DB_PATH = config.PREFIX .. "/var/lib/pkglet"
    config.CACHE_PATH = "/var/cache/pkglet"
    config.BUILD_PATH = config.CACHE_PATH .. "/build"
    config.TEMP_INSTALL_PATH = config.CACHE_PATH .. "/temp_install"
    config.DISTFILES_PATH = config.CACHE_PATH .. "/distfiles"
    config.CONFIG_DIR = "/etc/pkglet"
    config.REPOS_CONF = config.CONFIG_DIR .. "/repos.conf"
    config.MAKE_CONF = config.CONFIG_DIR .. "/make.lua"
    config.PACKAGE_OPTS = config.CONFIG_DIR .. "/package.opts"
    config.PACKAGE_MASK = config.CONFIG_DIR .. "/package.mask"
    config.PACKAGE_LOCK = config.CONFIG_DIR .. "/package.lock"
end

config.global_options = {}
config.package_options = {}
config.masked_packages = {}
config.pinned_packages = {}
config.repos = {}
config.noask = false
function config.init()
    os.execute("mkdir -p " .. config.DB_PATH)
    os.execute("mkdir -p " .. config.BUILD_PATH)
    os.execute("mkdir -p " .. config.DISTFILES_PATH)
    os.execute("mkdir -p " .. config.TEMP_INSTALL_PATH)
    config.load_repos()
    config.load_package_options()
    config.load_masks()
    config.load_pins()
end
function config.load_repos()
    local f = io.open(config.REPOS_CONF, "r")
    if not f then return end
    for _line in f:lines() do
        local line = _line:gsub("#.*", ""):match("^%s*(.-)%s*$")
        if line ~= "" then
            local name, path = line:match("^(%S+)%s+(%S+)$")
            if name and path then
                if path:match("^https?://") or path:match("^git@") or path:match("%.git$") then
                    config.repos[name] = { url = path, is_git = true }
                else
                    config.repos[name] = { path = path, is_git = false }
                end
            end
        end
    end
    f:close()
end

function config.load_package_options()
    local handle = io.popen("find " .. config.PACKAGE_OPTS .. " -type f 2>/dev/null")
    if not handle then return end
    for filepath in handle:lines() do
        local pkg = filepath:match("([^/]+)$")
        if pkg then
            config.package_options[pkg] = {}
            local f = io.open(filepath, "r")
            if f then
                for _line in f:lines() do
                    local line = _line:gsub("#.*", ""):match("^%s*(.-)%s*$")
                    if line ~= "" then
                        for opt in line:gmatch("%S+") do
                            config.package_options[pkg][opt] = true
                        end
                    end
                end
                f:close()
            end
        end
    end
    handle:close()
end

function config.load_masks()
    local f = io.open(config.PACKAGE_MASK, "r")
    if not f then return end
    for _line in f:lines() do
        local line = _line:gsub("#.*", ""):match("^%s*(.-)%s*$")
        if line ~= "" then
            local repo, pkg = line:match("^([^/]+)/(.+)$")
            if repo and pkg then
                if not config.masked_packages[repo] then
                    config.masked_packages[repo] = {}
                end
                config.masked_packages[repo][pkg] = true
            else
                config.masked_packages[line] = true
            end
        end
    end
    f:close()
end

function config.get_make_opts()
    local opts = {
        jobs = 1,
        load = 1,
        extra = "",
        default_build_mode = "binary",
    }

    local f = io.open(config.MAKE_CONF, "r")
    if f then
        local chunk = f:read("*a")
        f:close()
        local env = {}
        local fn = load(chunk, config.MAKE_CONF, "t", env)
        if fn then
            pcall(fn)
            if env.MAKEOPTS then opts = env.MAKEOPTS end
            if env.default_build_mode then
                opts.default_build_mode = env.default_build_mode
            end
            if env.jobs then
                opts.jobs = env.jobs
            end
            if env.load then
                opts.load = env.load
            end
            if env.extra then
                opts.extra = env.extra
            end
        end
    end
    return opts
end

function config.set_bootstrap_root(path)
    config.PREFIX = path
    config.ROOT = path .. "/"
    local marker = path .. "/var/.pkglet"
    local f = io.open(marker, "r")
    if f then
        f:close()
        config.DB_PATH = path .. "/var/lib/pkglet/"
    end
end

function config.load_pins()
    local f = io.open(config.PACKAGE_LOCK, "r")
    if not f then return end
    for _line in f:lines() do
        local line = _line:gsub("#.*", ""):match("^%s*(.-)%s*$")
        if line ~= "" then
            local pkg, version = line:match("^([^%s]+)%s+(.+)$")
            if pkg and version then
                config.pinned_packages[pkg] = version
            end
        end
    end
    f:close()
end

function config.add_repo(name, path)
    local repo_entry
    if path:match("^https?://") or path:match("^git@") or path:match("%.git$") then
        repo_entry = { url = path, is_git = true }
    else
        repo_entry = { path = path, is_git = false }
    end
    config.repos[name] = repo_entry

    local f = io.open(config.REPOS_CONF, "a")
    if f then
        f:write(name .. " " .. path .. "\n")
        f:close()
    end
end

function config.remove_repo(name)
    config.repos[name] = nil

    local lines = {}
    local f = io.open(config.REPOS_CONF, "r")
    if f then
        for line in f:lines() do
            if not line:match("^" .. name .. "%s+") then
                table.insert(lines, line)
            end
        end
        f:close()
    end

    f = io.open(config.REPOS_CONF, "w")
    if f then
        for _, line in ipairs(lines) do
            f:write(line .. "\n")
        end
        f:close()
    end
end

function config.ensure_repo(name)
    local repo = config.repos[name]
    if not repo then
        return nil
    end

    if repo.is_git then
        local target_path = config.CACHE_PATH .. "/repos/" .. name
        if not config.repo_exists(target_path) then
            print("Cloning repository " .. name .. "...")
            local ok = os.execute("mkdir -p " .. config.CACHE_PATH .. "/repos")
            if ok then
                ok = os.execute("git clone " .. repo.url .. " " .. target_path)
                if not ok then
                    error("failed to clone repository: " .. repo.url)
                end
            end
        end
        return target_path
    else
        return repo.path
    end
end

function config.repo_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

function config.is_pinned(package_name)
    return config.pinned_packages[package_name]
end

function config.pin_package(package_name, version)
    config.pinned_packages[package_name] = version

    local f = io.open(config.PACKAGE_LOCK, "a")
    if f then
        f:write(package_name .. " " .. version .. "\n")
        f:close()
    end
end

function config.unpin_package(package_name)
    config.pinned_packages[package_name] = nil

    local lines = {}
    local f = io.open(config.PACKAGE_LOCK, "r")
    if f then
        for line in f:lines() do
            if not line:match("^" .. package_name .. "%s+") then
                table.insert(lines, line)
            end
        end
        f:close()
    end

    f = io.open(config.PACKAGE_LOCK, "w")
    if f then
        for _, line in ipairs(lines) do
            f:write(line .. "\n")
        end
        f:close()
    end
end

return config
