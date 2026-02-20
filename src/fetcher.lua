--- Source fetching module
-- @module fetcher

local fetcher = {}
local config = require("src.config")

function fetcher.fetch(source_spec, build_dir, options)
	if type(source_spec) == "table" then
		if source_spec[1] then
			return fetcher.fetch_all(source_spec, build_dir)
		else
			return fetcher.fetch_single(source_spec, build_dir)
		end
	else
		error("invalid source specification")
	end
end

function fetcher.fetch_single(spec, build_dir, options)
	if spec.type == "tar" then
		return fetcher.fetch_tar(spec, build_dir)
	elseif spec.type == "git" then
		return fetcher.fetch_git(spec, build_dir)
	elseif spec.type == "file" then
		return fetcher.fetch_file(spec, build_dir)
	else
		error("unsupported source type: " .. tostring(spec.type))
	end
end

function fetcher.fetch_all(sources, build_dir)
	os.execute("mkdir -p " .. build_dir)
	for _, spec in ipairs(sources) do
		if spec.type == "tar" then
			fetcher.fetch_tar(spec, build_dir)
		elseif spec.type == "file" then
			fetcher.fetch_file(spec, build_dir)
		else
			error("unsupported source type in multi-source: " .. tostring(spec.type))
		end
	end
	for _, spec in ipairs(sources) do
		if spec.patches then
			fetcher.apply_patches(spec.patches, build_dir)
		end
	end
	return build_dir
end

function fetcher.fetch_tar(spec, build_dir)
    spec.args = spec.args or ""
	local filename = spec.url:match("([^/]+)$")
	local distfile = config.DISTFILES_PATH .. "/" .. filename
	if not fetcher.file_exists(distfile) then
		print("Fetching " .. filename .. "...")

		local success = false
		if spec.url:match("^https?://") then
			local ok, _, code = os.execute("wget -O " .. distfile .. " " .. spec.url)
			if ok and code == 0 then
				success = true
			end
		else
			local ok, _, code = os.execute("cp " .. spec.url .. " " .. distfile)
			if ok and code == 0 then
				success = true
			end
		end

		if not success then
			error("failed to download: " .. spec.url)
		end
	end

	if spec.sha256sum then
		local ok = fetcher.verify_sha256(distfile, spec.sha256sum)
		if not ok then
			error("sha256sum mismatch for " .. filename)
		end
	elseif spec.md5sum then
		local ok = fetcher.verify_md5(distfile, spec.md5sum)
		if not ok then
			error("md5sum mismatch for " .. filename)
		end
	end

	os.execute("mkdir -p " .. build_dir)
	print("Extracting " .. filename .. "...")
	local extract_cmd
	if filename:match("%.tar%.gz$") or filename:match("%.tgz$") then
		extract_cmd = "tar xzf " .. distfile .. " -C " .. build_dir .. " " .. spec.args
	elseif filename:match("%.tar%.bz2$") or filename:match("%.tbz2$") then
		extract_cmd = "tar xjf " .. distfile .. " -C " .. build_dir .. " " .. spec.args
	elseif filename:match("%.tar%.xz$") or filename:match("%.txz$") then
		extract_cmd = "tar xJf " .. distfile .. " -C " .. build_dir .. " " .. spec.args
	elseif filename:match("%.zip$") then
		extract_cmd = "unzip -q " .. distfile .. " -d " .. build_dir .. " " .. spec.args
	else
		extract_cmd = "tar xf " .. distfile .. " -C " .. build_dir .. " " .. spec.args
	end
	local ok, _, code = os.execute(extract_cmd)
	if not ok or code ~= 0 then
		error("failed to extract: " .. filename)
	end
	return build_dir
end

function fetcher.fetch_git(spec, build_dir)
	print("Cloning " .. spec.url .. "...")
	local clone_cmd = "git clone " .. spec.url .. " " .. build_dir
	if spec.commit then
		clone_cmd = clone_cmd .. " && cd " .. build_dir .. " && git checkout " .. spec.commit
	elseif spec.tag then
		clone_cmd = clone_cmd .. " --branch " .. spec.tag
	end
	local ok, _, code = os.execute(clone_cmd)
	if not ok or code ~= 0 then
		error("failed to clone: " .. spec.url)
	end
	return build_dir
end

function fetcher.fetch_file(spec, build_dir)
	local filename = spec.name or spec.url:match("([^/]+)$")
	local distfile = config.DISTFILES_PATH .. "/" .. (spec.name or spec.url:match("([^/]+)$"))
	if not fetcher.file_exists(distfile) then
		print("Fetching " .. filename .. "...")

		local success = false
		if spec.url:match("^https?://") then
			local ok, _, code = os.execute("wget -O " .. distfile .. " " .. spec.url)
			if ok and code == 0 then
				success = true
			end
		else
			local ok, _, code = os.execute("cp " .. spec.url .. " " .. distfile)
			if ok and code == 0 then
				success = true
			end
		end

		if not success then
			error("failed to download: " .. spec.url)
		end
	end

	if spec.sha256sum then
		local ok = fetcher.verify_sha256(distfile, spec.sha256sum)
		if not ok then
			error("sha256sum mismatch for " .. filename)
		end
	elseif spec.md5sum then
		local ok = fetcher.verify_md5(distfile, spec.md5sum)
		if not ok then
			error("md5sum mismatch for " .. filename)
		end
	end

	os.execute("mkdir -p " .. build_dir)
	os.execute("cp " .. distfile .. " " .. build_dir .. "/" .. filename)
	return build_dir
end

function fetcher.apply_patches(patches, build_dir)
	for _, patch in ipairs(patches) do
		local patch_file = fetcher.fetch_patch(patch, build_dir)
		print("Applying patch: " .. patch_file)
		local ok, _, code = os.execute("cd " .. build_dir .. " && patch -p0 < " .. patch_file)
		if not ok or code ~= 0 then
			if patch.nofail then
				print("Warning: failed to apply patch: " .. patch.url)
			else
				error("failed to apply patch: " .. patch.url)
			end
		end
	end
end

function fetcher.fetch_patch(patch_spec, build_dir)
	local filename = patch_spec.name or patch_spec.url:match("([^/]+)$")
	local patchfile = config.DISTFILES_PATH .. "/" .. filename
	if not fetcher.file_exists(patchfile) then
		print("Fetching patch: " .. filename .. "...")
		local success = false
		if patch_spec.url:match("^https?://") then
			local ok, _, code = os.execute("wget -O " .. patchfile .. " " .. patch_spec.url)
			if ok and code == 0 then
				success = true
			end
		else
			local ok, _, code = os.execute("cp " .. patch_spec.url .. " " .. patchfile)
			if ok and code == 0 then
				success = true
			end
		end
		if not success then
			error("failed to download patch: " .. patch_spec.url)
		end
	end

	if patch_spec.sha256sum then
		local ok = fetcher.verify_sha256(patchfile, patch_spec.sha256sum)
		if not ok then
			error("sha256sum mismatch for patch: " .. filename)
		end
	elseif patch_spec.md5sum then
		local ok = fetcher.verify_md5(patchfile, patch_spec.md5sum)
		if not ok then
			error("md5sum mismatch for patch: " .. filename)
		end
	end

	return patchfile
end

function fetcher.verify_sha256(file, expected)
	local handle = io.popen("sha256sum " .. file)
	local result = handle:read("*a")
	handle:close()
	local actual = result:match("^([a-f0-9]+)")
	return actual == expected
end

function fetcher.verify_md5(file, expected)
	local handle = io.popen("md5sum " .. file)
	local result = handle:read("*a")
	handle:close()
	local actual = result:match("^([a-f0-9]+)")
	return actual == expected
end
function fetcher.file_exists(path)
	local f = io.open(path, "r")
	if f then
		f:close()
		return true
	end
	return false
end

return fetcher
