require("swupdate")

mxl_img_handler = function(image)
	swupdate.notify(swupdate.RECOVERY_STATUS.IDLE, 0, "Maxlinear image installation in progress...")

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
		swupdate.info("Authenticating ext4 image (secupg -e): " .. image.filename)
		cmd = "secupg -e " .. tmpfile

		if not os.execute(cmd) then
			swupdate.error("Ext4 image " .. image.filename .. " verification failed")
			return 1
		end

		swupdate.notify(swupdate.RECOVERY_STATUS.RUN, 0,
						"Maxlinear image " .. image.filename .. " verification success")
	else
		swupdate.info("Authenticating " .. image.filename)
		cmd = "secupg -a " .. tmpfile

		if not os.execute(cmd) then
			swupdate.error("Image " .. image.filename .. " verification failed")
			return 1
		end

		swupdate.notify(swupdate.RECOVERY_STATUS.RUN, 0,
						"Maxlinear image " .. image.filename .. " verification success")
	end

	-- Check if in dry-run mode
	-- RUN_DEFAULT = 0, RUN_DRYRUN = 1, RUN_INSTALL = 2
	if swupdate.is_dryrun == 1 then
		-- Dry-run mode: skip installation
		swupdate.notify(swupdate.RECOVERY_STATUS.RUN, 0, "Dry run - skipping installation")
	elseif image.filename == "u-boot-spl-emmc.bin" then
		swupdate.notify(swupdate.RECOVERY_STATUS.RUN, 0,
						"Installing " .. image.filename .. " to " .. image.device)

		local stripped = tmpfile .. ".stripped"

		-- Strip mkimage header
		cmd = string.format("dd if=%s of=%s bs=%d skip=1 2>/dev/null",
			tmpfile, stripped, MKIMAGE_HDR_SIZE)
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

		swupdate.notify(swupdate.RECOVERY_STATUS.RUN, 0,
						"Successfully installed " .. image.filename .. " to " .. image.device)
	else
		image.type = "gptpart"
		swupdate.notify(swupdate.RECOVERY_STATUS.RUN, 0,
						"Installing " .. image.filename .. " to partition " .. image.volume)

		-- Call gptpart handler to write the image
		ret = swupdate.call_handler(image.type, image)
		if ret ~= 0 then
			swupdate.error("Failed to write " .. image.filename .. " to partition " .. image.volume)
			return ret
		end
		swupdate.notify(swupdate.RECOVERY_STATUS.RUN, 0,
						"Successfully installed " .. image.filename .. " to partition " .. image.volume)
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

		swupdate.notify(swupdate.RECOVERY_STATUS.RUN, 0,
						"Successfully installed " .. image.filename .. " to " .. image.device)
		return ret
	end
end

swupdate.register_handler("mxl_imghdlr", mxl_img_handler, swupdate.HANDLER_MASK.IMAGE_HANDLER)
swupdate.register_handler("mxl_rbehdlr", mxl_rbe_handler, swupdate.HANDLER_MASK.IMAGE_HANDLER)
