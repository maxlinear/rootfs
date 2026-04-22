#!/bin/sh /etc/rc.common

START=99

start() {
	local rbe_upgrade size
	rbe_upgrade="$(fw_printenv -n rbe_upgrade 2>/dev/null)"

	if [ "$rbe_upgrade" != "1" ]; then
		return 0
	fi

	logger -t upgrade-rbe "rbe_upgrade=1 detected, syncing RBE to boot1"

	# Disable write protection on boot1
	echo 0 > /sys/block/mmcblk0boot1/force_ro
	if [ "$(cat /sys/block/mmcblk0boot1/force_ro)" != "0" ]; then
		logger -t upgrade-rbe "Failed to disable write protection on mmcblk0boot1"
		return 1
	fi

	# Get boot0 size
	size="$(cat /sys/block/mmcblk0boot0/size)"
	if [ -z "$size" ]; then
		logger -t upgrade-rbe "Failed to read mmcblk0boot0 size"
		echo 1 > /sys/block/mmcblk0boot1/force_ro
		return 1
	fi

	# Copy boot0 to boot1
	dd if=/dev/mmcblk0boot0 of=/dev/mmcblk0boot1 bs=512 count="$size" 2>/dev/null
	if [ $? -ne 0 ]; then
		logger -t upgrade-rbe "Failed to copy mmcblk0boot0 to mmcblk0boot1"
		echo 1 > /sys/block/mmcblk0boot1/force_ro
		return 1
	fi

	# Verify boot0 and boot1 have identical data
	local hash_boot0 hash_boot1
	hash_boot0="$(dd if=/dev/mmcblk0boot0 bs=512 count="$size" 2>/dev/null | sha256sum | awk '{print $1}')"
	hash_boot1="$(dd if=/dev/mmcblk0boot1 bs=512 count="$size" 2>/dev/null | sha256sum | awk '{print $1}')"
	if [ "$hash_boot0" != "$hash_boot1" ]; then
		logger -t upgrade-rbe "Verification failed: boot0($hash_boot0) != boot1($hash_boot1)"
		echo 1 > /sys/block/mmcblk0boot1/force_ro
		return 1
	fi
	logger -t upgrade-rbe "Verification passed: boot0 and boot1 match ($hash_boot0)"

	# Re-enable write protection on boot1
	echo 1 > /sys/block/mmcblk0boot1/force_ro

	# Clear the rbe_upgrade flag
	fw_setenv rbe_upgrade 0
	logger -t upgrade-rbe "RBE sync complete, rbe_upgrade cleared"
}
