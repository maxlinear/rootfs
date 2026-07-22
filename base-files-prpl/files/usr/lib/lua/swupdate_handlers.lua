require("swupdate")

-- update_filesize: updates rootfs_a_filesize in the u-boot environment after a
-- successful ext4.img write.

update_filesize = function(image)
	local mnt = "/tmp/ext4mnt"
	os.execute("mkdir -p " .. mnt)

	if not os.execute("mount -o loop,ro,noload,norecovery -t ext4 " .. "/tmp/" .. image.filename .. " " .. mnt) then
		swupdate.error("Failed to mount " .. image.filename)
		return 1
	end

	local p = io.popen("stat -c %s /tmp/ext4mnt/rootfs.itb")
	local size = p:read("*a")
	p:close()
	os.execute("umount " .. mnt)
	size = tonumber(size)

	if not size then
		swupdate.error("Failed to get rootfs.itb size")
		return 1
	end

	-- format the size as an 8-digit lower-case hex string (e.g. "00a3c000").
	local size_hex = string.format("%08x", size)
	local varname = "rootfs_a_filesize"

	-- Return true if varname exists in the u-boot environment.
	local function env_exists(vname)
		local p = io.popen("fw_printenv " .. vname .. " 2>/dev/null")
		if not p then return false end
		local out = p:read("*a")
		p:close()
		return out:match("^" .. vname .. "=") ~= nil
	end

	-- Check if rootfs_a_filesize exists in the u-boot environment, create it if not.
	if not env_exists(varname) then
		if not os.execute("fw_setenv " .. varname .. " 0") then
			swupdate.error("update_filesize: failed to create " .. varname)
			return 1
		end
	end

	-- Set rootfs_a_filesize to the size of rootfs.itb in hex format in the u-boot environment.
	if not os.execute("fw_setenv " .. varname .. " " .. size_hex) then
		swupdate.error("update_filesize: failed to set " .. varname)
		return 1
	end

	return 0
end

mxl_img_handler = function(image)
	swupdate.trace("Image installation is in progress...")

	-- Make sure that gptpart handler exists
	if not swupdate.handler["gptpart"] then
		swupdate.error("gptpart handler not available")
		return 1
	end

	local MKIMAGE_HDR_SIZE = 64
	local cmd, ret = nil, 0
	local tmpfile = swupdate.tmpdir() .. image.filename

	-- Authenticate images using secupg
	if image.filename == "ext4.img" then
		swupdate.trace("Authenticating kernel and rootfs images")
		cmd = "secupg -e " .. tmpfile

		if not os.execute(cmd) then
			swupdate.error("kernel.itb and rootfs.itb images verification failed...")
			return 1
		end

		swupdate.trace("kernel.itb and rootfs.itb images verification success")
	else
		swupdate.trace("Authenticating " .. image.filename .. " image")
		cmd = "secupg -a " .. tmpfile

		if not os.execute(cmd) then
			swupdate.error("Image " .. image.filename .. " verification failed...")
			return 1
		end

		swupdate.trace("Image " .. image.filename .. " verification success")
	end

	-- Check if in dry-run mode
	-- RUN_DEFAULT = 0, RUN_DRYRUN = 1, RUN_INSTALL = 2
	if swupdate.is_dryrun == 1 then
		-- Dry-run mode: skip installation
		swupdate.trace("Dry run - skipping installation")

	elseif image.filename == "u-boot-spl-emmc.bin" then
		swupdate.trace("Installing " .. image.filename .. " to " .. image.device)

		local stripped = tmpfile .. ".stripped"

		-- Strip mkimage header
		cmd = string.format(
			"dd if=%s of=%s bs=%d skip=1 2>/dev/null",
			tmpfile, stripped, MKIMAGE_HDR_SIZE
		)

		if not os.execute(cmd) then
			swupdate.error("Failed to strip mkimage header from " .. tmpfile)
			return 1
		end

		-- Compute sha256 of the stripped payload
		local p = io.popen("sha256sum " .. stripped)
		local hash = p:read("*a"):match("^(%x+)")
		p:close()

		if not hash or #hash ~= 64 then
			swupdate.error("Failed to compute sha256 of stripped RBE")
			os.remove(stripped)
			return 1
		end

		-- Replace istream with the stripped file so call_handler reads payload only
		local new_stream = io.open(stripped, "r")
		if not new_stream then
			swupdate.error("Failed to open stripped file " .. stripped)
			os.remove(stripped)
			return 1
		end

		local new_size = new_stream:seek("end")
		new_stream:seek("set", 0)

		image._private.istream:close()
		image._private.istream = new_stream
		image._private.offset = 0
		image.sha256 = hash
		image.size = new_size
		image.type = "raw"

		-- Call raw handler to write the image
		ret = swupdate.call_handler(image.type, image)
		os.remove(stripped)

		if ret ~= 0 then
			swupdate.error("Failed to write " .. image.filename .. " to " .. image.device)
			return ret
		end

		swupdate.trace("Successfully installed " .. image.filename .. " to " .. image.device)

	else
		image.type = "gptpart"

		if image.filename == "ext4.img" then
			swupdate.trace("Installing kernel.itb and rootfs.itb images to " .. image.volume .. " partition")
		else
			swupdate.trace("Installing " .. image.filename .. " to " .. image.volume .. " partition")
		end

		-- Call gptpart handler to write the image
		ret = swupdate.call_handler(image.type, image)

		if ret ~= 0 then
			swupdate.error("Failed to write " .. image.filename .. " to " .. image.volume .. " partition")
			return ret
		end

		-- updates rootfs_a_filesize.
		if image.filename == "ext4.img" then
			ret = update_filesize(image)

			if ret ~= 0 then
				swupdate.error("Failed to update rootfs_a_filesize for " .. image.filename)
				return ret
			end
		end

		if image.filename == "ext4.img" then
			swupdate.trace("Successfully installed kernel.itb and rootfs.itb images to " .. image.volume .. " partition")
		else
			swupdate.trace("Successfully installed " .. image.filename .. " to " .. image.volume .. " partition")
		end
	end

	-- Set u-boot environment variable to signal RBE upgrade
	cmd = "fw_setenv rbe_upgrade 1"

	if not os.execute(cmd) then
		swupdate.error("Failed to set u-boot environment variable rbe_upgrade")
		return 1
	end

	return 0
end

mxl_rbe_handler = function(image)
	if image.filename == "u-boot-spl-emmc.bin" then
		local cmd, ret = nil, 0

		cmd = "fw_setenv rbe_upgrade 1"

		-- Set u-boot environment variable to signal RBE upgrade
		if not os.execute(cmd) then
			swupdate.error("Failed to set u-boot environment variable rbe_upgrade")
			return 1
		end

		-- Set type to raw and call handler
		image.type = "raw"
		ret = swupdate.call_handler(image.type, image)

		if ret ~= 0 then
			swupdate.error("Failed to write " .. image.filename .. " to " .. image.device)
			return ret
		end

		swupdate.trace("Successfully installed " .. image.filename .. " to " .. image.device)

		return ret
	end
end

swupdate.register_handler("mxl_imghdlr", mxl_img_handler, swupdate.HANDLER_MASK.IMAGE_HANDLER)
swupdate.register_handler("mxl_rbehdlr", mxl_rbe_handler, swupdate.HANDLER_MASK.IMAGE_HANDLER)
