--- GPG package signing and verification module
--
-- This module provides comprehensive cryptographic verification capabilities
-- for packages using GPG (GNU Privacy Guard). It supports package signing,
-- signature verification, key management, and trust validation. The system
-- ensures package integrity and authenticity through digital signatures,
-- protecting against tampering and unauthorized distribution.
--
-- The module implements secure key storage, signature verification workflows,
-- and trust chain validation. It supports both individual package signatures
-- and repository-level signatures, with configurable trust policies and
-- automatic key retrieval from key servers when needed.
-- @module gpg

local gpg = {}
local config = require("src.config")

--- Initialize GPG environment and ensure necessary directories exist
-- This function creates the GPG home directory and initializes the
-- keyring if it doesn't exist. It sets up the secure environment
-- needed for cryptographic operations.
function gpg.init()
    os.execute("mkdir -p " .. config.GPG_HOME)
    os.execute("chmod 700 " .. config.GPG_HOME)
    
    if not gpg.keyring_exists() then
        os.execute("gpg --homedir " .. config.GPG_HOME .. " --list-keys >/dev/null 2>&1 || true")
    end
end

--- Check if GPG keyring exists
-- @return boolean True if keyring exists, false otherwise
function gpg.keyring_exists()
    local f = io.open(config.GPG_HOME .. "/pubring.kbx", "r")
    if f then
        f:close()
        return true
    end
    f = io.open(config.GPG_HOME .. "/pubring.gpg", "r")
    if f then
        f:close()
        return true
    end
    return false
end

--- Import a GPG key from file or key server
-- @param key_source string Path to key file or key ID (for key server)
-- @param from_keyserver boolean Whether to fetch from key server
-- @return boolean True if key imported successfully
function gpg.import_key(key_source, from_keyserver)
    local cmd
    
    if from_keyserver then
        cmd = "gpg --homedir " .. config.GPG_HOME .. " --keyserver hkps://keys.openpgp.org --recv-keys " .. key_source
    else
        cmd = "gpg --homedir " .. config.GPG_HOME .. " --import " .. key_source
    end
    
    local ok, _, code = os.execute(cmd)
    if ok and code == 0 then
        print("GPG key imported successfully: " .. key_source)
        return true
    else
        print("Failed to import GPG key: " .. key_source)
        return false
    end
end

--- Create a GPG signature for a package
-- @param package_file string Path to package file to sign
-- @param key_id string GPG key ID to use for signing (optional)
-- @return boolean True if signature created successfully
function gpg.sign_package(package_file, key_id)
    local cmd = "gpg --homedir " .. config.GPG_HOME
    if key_id then
        cmd = cmd .. " --local-user " .. key_id
    end
    cmd = cmd .. " --detach-sign --armor " .. package_file
    
    local ok, _, code = os.execute(cmd)
    if ok and code == 0 then
        print("Package signed successfully: " .. package_file)
        return true
    else
        print("Failed to sign package: " .. package_file)
        return false
    end
end

--- Verify a GPG signature for a package
-- @param package_file string Path to package file
-- @param signature_file string Path to signature file (optional, auto-detected)
-- @return table Verification result with status, key info, and trust level
function gpg.verify_package(package_file, signature_file)
    local sig_file = signature_file or package_file .. ".asc"
    
    if not io.open(sig_file, "r") then
        return {
            status = "error",
            error = "Signature file not found: " .. sig_file
        }
    end
    
    local cmd = "gpg --homedir " .. config.GPG_HOME .. " --verify " .. sig_file .. " " .. package_file .. " 2>&1"
    local handle = io.popen(cmd)
    local output = handle:read("*a")
    local success = handle:close()
    
    local result = gpg.parse_gpg_output(output)
    
    if result.status == "valid" then
        result.key_trusted = gpg.is_key_trusted(result.key_id)
    end
    
    return result
end

--- Parse GPG verification output
-- @param output string GPG verification output
-- @return table Parsed verification result
function gpg.parse_gpg_output(output)
    local result = {
        status = "unknown",
        key_id = nil,
        key_fingerprint = nil,
        trust_level = nil
    }
    
    if output:match("Good signature") then
        result.status = "valid"
        result.key_id = output:match("using [^%s]+ key ([A-F0-9]+)")
    elseif output:match("BAD signature") then
        result.status = "invalid"
        result.key_id = output:match("using [^%s]+ key ([A-F0-9]+)")
    elseif output:match("No public key") then
        result.status = "no_key"
        result.key_id = output:match("ID ([A-F0-9]+)")
    elseif output:match("Can't check signature") then
        result.status = "error"
    end
    
    return result
end

--- Check if a GPG key is trusted
-- @param key_id string GPG key ID
-- @return boolean True if key is trusted
function gpg.is_key_trusted(key_id)
    if not key_id then return false end
    
    local cmd = "gpg --homedir " .. config.GPG_HOME .. " --list-keys --with-colons " .. key_id .. " 2>/dev/null"
    local handle = io.popen(cmd)
    local output = handle:read("*a")
    handle:close()
    
    if output:match("^pub:[^:]*:[^:]*:[^:]*:[^:]*:u:") then
        return true
    elseif output:match("^pub:[^:]*:[^:]*:[^:]*:[^:]*:f:") then
        return true
    elseif output:match("^pub:[^:]*:[^:]*:[^:]*:[^:]*:m:") then
        return true
    end
    
    return false
end

--- Sign a repository metadata file
-- @param metadata_file string Path to repository metadata file
-- @param key_id string GPG key ID (optional)
-- @return boolean True if signed successfully
function gpg.sign_repository(metadata_file, key_id)
    return gpg.sign_package(metadata_file, key_id)
end

--- Verify repository metadata signature
-- @param metadata_file string Path to repository metadata file
-- @param signature_file string Path to signature file (optional)
-- @return table Verification result
function gpg.verify_repository(metadata_file, signature_file)
    return gpg.verify_package(metadata_file, signature_file)
end

--- List available GPG keys in keyring
-- @return table Array of key information
function gpg.list_keys()
    local keys = {}
    local cmd = "gpg --homedir " .. config.GPG_HOME .. " --list-keys --with-colons 2>/dev/null"
    local handle = io.popen(cmd)
    
    for line in handle:lines() do
        if line:match("^pub:") then
            local key_info = {}
            local parts = {}
            for part in line:gmatch("[^:]+") do
                table.insert(parts, part)
            end
            
            key_info.key_id = parts[5]
            key_info.creation_date = parts[6]
            key_info.expiration_date = parts[7]
            key_info.trust = parts[9]
            key_info.user_id = parts[10] or ""
            
            if #parts > 10 then
                for i = 11, #parts do
                    key_info.user_id = key_info.user_id .. ":" .. parts[i]
                end
            end
            
            key_info.trust_name = gpg.get_trust_name(key_info.trust)
            
            table.insert(keys, key_info)
        end
    end
    handle:close()
    
    return keys
end

--- Get human-readable trust level name
-- @param trust_code string GPG trust code
-- @return string Human-readable trust level
function gpg.get_trust_name(trust_code)
    local trust_names = {
        ["o"] = "unknown",
        ["i"] = "invalid",
        ["d"] = "disabled",
        ["r"] = "revoked",
        ["e"] = "expired",
        ["-"] = "unknown",
        ["q"] = "undefined",
        ["n"] = "never",
        ["m"] = "marginal",
        ["f"] = "full",
        ["u"] = "ultimate"
    }
    return trust_names[trust_code] or "unknown"
end

--- Generate a new GPG key pair
-- @param name string Real name for the key
-- @param email string Email address for the key
-- @param passphrase string Passphrase for the key (optional)
-- @return boolean True if key generated successfully
function gpg.generate_key(name, email, passphrase)
    local batch_file = os.tmpname()
    local f = io.open(batch_file, "w")
    
    if passphrase then
        f:write("Key-Type: RSA\n")
        f:write("Key-Length: 4096\n")
        f:write("Subkey-Type: RSA\n")
        f:write("Subkey-Length: 4096\n")
        f:write("Name-Real: " .. name .. "\n")
        f:write("Name-Email: " .. email .. "\n")
        f:write("Passphrase: " .. passphrase .. "\n")
        f:write("Expire-Date: 0\n")
        f:write("%commit\n")
        f:write("%echo done\n")
    else
        f:write("Key-Type: RSA\n")
        f:write("Key-Length: 4096\n")
        f:write("Subkey-Type: RSA\n")
        f:write("Subkey-Length: 4096\n")
        f:write("Name-Real: " .. name .. "\n")
        f:write("Name-Email: " .. email .. "\n")
        f:write("Expire-Date: 0\n")
        f:write("%commit\n")
        f:write("%echo done\n")
    end
    
    f:close()
    
    local cmd = "gpg --homedir " .. config.GPG_HOME .. " --batch --generate-key " .. batch_file
    local ok, _, code = os.execute(cmd)
    
    os.remove(batch_file)
    
    if ok and code == 0 then
        print("GPG key pair generated successfully")
        return true
    else
        print("Failed to generate GPG key pair")
        return false
    end
end

--- Export a public key to a file
-- @param key_id string GPG key ID
-- @param output_file string Path to output file
-- @return boolean True if exported successfully
function gpg.export_public_key(key_id, output_file)
    local cmd = "gpg --homedir " .. config.GPG_HOME .. " --armor --export " .. key_id .. " > " .. output_file
    local ok, _, code = os.execute(cmd)
    
    if ok and code == 0 then
        print("Public key exported to: " .. output_file)
        return true
    else
        print("Failed to export public key")
        return false
    end
end

--- Delete a key from the keyring
-- @param key_id string GPG key ID
-- @param secret boolean Whether to delete secret key too
-- @return boolean True if deleted successfully
function gpg.delete_key(key_id, secret)
    local cmd
    if secret then
        cmd = "gpg --homedir " .. config.GPG_HOME .. " --delete-secret-and-public-key --batch --yes " .. key_id
    else
        cmd = "gpg --homedir " .. config.GPG_HOME .. " --delete-key --batch --yes " .. key_id
    end
    
    local ok, _, code = os.execute(cmd)
    
    if ok and code == 0 then
        print("Key deleted successfully: " .. key_id)
        return true
    else
        print("Failed to delete key: " .. key_id)
        return false
    end
end

--- Check if GPG verification is enabled in configuration
-- @return boolean True if GPG verification is enabled
function gpg.is_enabled()
    return config.ENABLE_GPG ~= false
end

--- Get GPG configuration
-- @return table GPG configuration settings
function gpg.get_config()
    return {
        enabled = gpg.is_enabled(),
        home_dir = config.GPG_HOME,
        require_trusted = config.REQUIRE_TRUSTED_KEYS or false,
        auto_import_keys = config.AUTO_IMPORT_KEYS or false,
        key_server = config.KEY_SERVER or "hkps://keys.openpgp.org"
    }
end

return gpg