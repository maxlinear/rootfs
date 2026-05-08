#!/bin/sh /etc/rc.common

START=99

start() {
	local rbe_upgrade size booted_bank src dst
	rbe_upgrade="$(fw_printenv -n rbe_upgrade 2>/dev/null)"

	if [ "$rbe_upgrade" != "1" ]; then
		return 0
	fi

	# Determine which RBE bank was booted
	booted_bank="$(cat /proc/device-tree/chosen/u-boot,booted-rbe-bank | tr -d '\0')"
	if [ "$booted_bank" = "primary" ]; then
		src="mmcblk0boot0"
		dst="mmcblk0boot1"
		logger -t upgrade-rbe "rbe_upgrade=1 detected, booted from $booted_bank, syncing $src to $dst"
	elif [ "$booted_bank" = "backup" ]; then
		src="mmcblk0boot1"
		dst="mmcblk0boot0"
		logger -t upgrade-rbe "rbe_upgrade=1 detected, booted from $booted_bank, recovering $dst from $src"
	else
		logger -t upgrade-rbe "Unknown booted-rbe-bank value: '$booted_bank'"
		return 1
	fi

	# Disable write protection on destination
	echo 0 > /sys/block/$dst/force_ro
	if [ "$(cat /sys/block/$dst/force_ro)" != "0" ]; then
		logger -t upgrade-rbe "Failed to disable write protection on $dst"
		return 1
	fi

	# Get source size
	size="$(cat /sys/block/$src/size)"
	if [ -z "$size" ]; then
		logger -t upgrade-rbe "Failed to read $src size"
		echo 1 > /sys/block/$dst/force_ro
		return 1
	fi

	# Copy source to destination
	dd if=/dev/$src of=/dev/$dst bs=512 count="$size" 2>/dev/null
	if [ $? -ne 0 ]; then
		logger -t upgrade-rbe "Failed to copy $src to $dst"
		echo 1 > /sys/block/$dst/force_ro
		return 1
	fi

	# Verify source and destination have identical data
	local hash_src hash_dst
	hash_src="$(dd if=/dev/$src bs=512 count="$size" 2>/dev/null | sha256sum | awk '{print $1}')"
	hash_dst="$(dd if=/dev/$dst bs=512 count="$size" 2>/dev/null | sha256sum | awk '{print $1}')"
	if [ "$hash_src" != "$hash_dst" ]; then
		logger -t upgrade-rbe "Verification failed: $src($hash_src) != $dst($hash_dst)"
		echo 1 > /sys/block/$dst/force_ro
		return 1
	fi
	logger -t upgrade-rbe "Verification passed: $src and $dst match ($hash_src)"

	# Re-enable write protection on destination
	echo 1 > /sys/block/$dst/force_ro

	# Clear the rbe_upgrade flag
	fw_setenv rbe_upgrade 0
	logger -t upgrade-rbe "RBE sync complete"
}
