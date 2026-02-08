--- Source fetching module
-- @module fetcher

local fetcher = {}
local config = require("src.config")

--- Fetch source based on specification from remote repositories
-- This function serves as the main entry point for source acquisition in the pkglet system.
-- It dispatches to appropriate fetch handlers based on the source type, supporting tar archives,
-- git repositories, and individual files. The function ensures that sources are downloaded
-- to a centralized cache and extracted to the specified build directory for subsequent
-- compilation and installation steps.
-- @param source_spec table Source specification containing type, url, and optional metadata like checksums, commits, or tags
-- @param build_dir string Target build directory path where sources will be extracted and prepared for compilation
-- @return string The build directory path where sources were successfully extracted
function fetcher.fetch(source_spec, build_dir)
	if source_spec.type == "tar" then
		return fetcher.fetch_tar(source_spec, build_dir)
	elseif source_spec.type == "git" then
		return fetcher.fetch_git(source_spec, build_dir)
	elseif source_spec.type == "file" then
		return fetcher.fetch_file(source_spec, build_dir)
	else
		error("unsupported source type: " .. tostring(source_spec.type))
	end
end

--- Fetch and extract tar archive from remote URL with intelligent format detection
-- This function handles downloading and extracting compressed archives in various formats
-- including tar.gz, tar.bz2, tar.xz, and zip files. It implements caching to avoid
-- re-downloading the same archive and automatically detects the compression format
-- based on file extension. The extraction process strips the top-level directory
-- to ensure a clean build structure, which is essential for consistent compilation
-- across different upstream archive layouts.
-- @param spec table Archive specification containing url and optional checksum for verification
-- @param build_dir string Target directory where archive contents will be extracted for building
-- @return string The build directory path containing the extracted archive contents
function fetcher.fetch_tar(spec, build_dir)
	local filename = spec.url:match("([^/]+)$")
	local distfile = config.DISTFILES_PATH .. "/" .. filename
	if not fetcher.file_exists(distfile) then
		print("Fetching " .. filename .. "...")
		local ok, _, code = os.execute("wget -O " .. distfile .. " " .. spec.url)
		if not ok or code ~= 0 then
			error("failed to download: " .. spec.url)
		end
	end
	os.execute("mkdir -p " .. build_dir)
	print("Extracting " .. filename .. "...")
	local extract_cmd
	if filename:match("%.tar%.gz$") or filename:match("%.tgz$") then
		extract_cmd = "tar xzf " .. distfile .. " -C " .. build_dir .. " --strip-components=1"
	elseif filename:match("%.tar%.bz2$") or filename:match("%.tbz2$") then
		extract_cmd = "tar xjf " .. distfile .. " -C " .. build_dir .. " --strip-components=1"
	elseif filename:match("%.tar%.xz$") or filename:match("%.txz$") then
		extract_cmd = "tar xJf " .. distfile .. " -C " .. build_dir .. " --strip-components=1"
	elseif filename:match("%.zip$") then
		extract_cmd = "unzip -q " .. distfile .. " -d " .. build_dir
	else
		extract_cmd = "tar xf " .. distfile .. " -C " .. build_dir .. " --strip-components=1"
	end
	local ok, _, code = os.execute(extract_cmd)
	if not ok or code ~= 0 then
		error("failed to extract: " .. filename)
	end
	return build_dir
end

--- Clone git repository with support for specific commits, tags, or branches
-- This function handles cloning git repositories from remote URLs, providing flexibility
-- to checkout specific commits, tags, or branches for reproducible builds. It creates
-- a clean clone in the specified build directory and automatically switches to the
-- requested revision if specified. This ensures that package builds use exactly the
-- intended source code version, which is critical for security and reproducibility
-- in package management systems.
-- @param spec table Git repository specification containing url, optional commit hash, or tag name
-- @param build_dir string Target directory where the git repository will be cloned for building
-- @return string The build directory path containing the cloned git repository
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

--- Download individual file from remote URL with caching support
-- This function handles downloading single files from remote locations, implementing
-- the same caching mechanism as archives to avoid redundant downloads. It's particularly
-- useful for packages that consist of single files or patches that need to be applied
-- during the build process. The downloaded file is copied to the build directory,
-- maintaining the original filename while ensuring it's available for subsequent
-- build steps without requiring network access during the actual compilation.
-- @param spec table File specification containing the remote URL to download
-- @param build_dir string Target directory where the downloaded file will be copied for building
-- @return string The build directory path containing the downloaded file
function fetcher.fetch_file(spec, build_dir)
	local filename = spec.url:match("([^/]+)$")
	local distfile = config.DISTFILES_PATH .. "/" .. filename
	if not fetcher.file_exists(distfile) then
		print("Fetching " .. filename .. "...")
		local ok, _, code = os.execute("wget -O " .. distfile .. " " .. spec.url)
		if not ok or code ~= 0 then
			error("failed to download: " .. spec.url)
		end
	end
	os.execute("mkdir -p " .. build_dir)
	os.execute("cp " .. distfile .. " " .. build_dir .. "/")
	return build_dir
end

--- Check if file exists at the specified path using safe file operations
-- This utility function provides a reliable method to test file existence without
-- generating errors or exceptions. It attempts to open the file in read mode and
-- immediately closes it, which is a cross-platform compatible approach to check
-- both file existence and readability. This function is used throughout the
-- fetching system to determine whether cached files need to be downloaded or
-- if they can be reused from previous operations.
-- @param path string Absolute or relative file path to check for existence
-- @return boolean True if the file exists and is readable, false otherwise
function fetcher.file_exists(path)
	local f = io.open(path, "r")
	if f then
		f:close()
		return true
	end
	return false
end

return fetcher
