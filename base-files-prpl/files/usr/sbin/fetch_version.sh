#!/bin/sh

bank=$1

# Validate input argument
if [ -n "$bank" ] && [ "$bank" != "active" ] && [ "$bank" != "inactive" ]; then
    echo "Invalid argument. Use 'active', 'inactive', or leave empty for both the banks."
    exit 1
fi


check_bank() {
	if [[ "$bank" != "active" && "$bank" != "inactive" ]]; then
		mkdir /tmp/kernel_active
		mkdir /tmp/kernel_inactive
		check_files active
		check_files inactive
		exit 1
	else 
		# Create directories for the specified bank
		mkdir /tmp/kernel_$bank
	fi
}

check_files() {
	if [[ $1 == "active" ]]; then
		mount -t ext4 /dev/mmcblk0p11 /tmp/kernel_active
		get_version $1
		unmount_filesystems active
	elif [[ $1 == "inactive" ]]; then
		mount -t ext4 /dev/mmcblk0p12 /tmp/kernel_inactive
		get_version $1
		unmount_filesystems inactive
	fi
}

get_version() {
	if [ "$(ls -A /tmp/kernel_$1)" ]; then
		kernel_file="/tmp/kernel_$1/openwrt-intel_x86-lgm-CBSP_B0-kernel.bin"
		rootfs_file="/tmp/kernel_$1/openwrt-intel_x86-lgm-CBSP_B0-squashfs-fs.rootfs"
		if [ ! -f "$kernel_file" ]; then
			echo "$1 kernel file not found: $kernel_file"
			return
		fi
		if [ ! -f "$rootfs_file" ]; then
			echo "$1 rootfs file not found: $rootfs_file"
			return
		fi
		kernel_version=$(fdtget "$kernel_file" /configurations/kernel-dtb-conf version 2>/dev/null)
		if [ $? -ne 0 ]; then
			echo "$1 kernel version: ERROR (fdtget failed for $kernel_file)"
		else
			echo "$1 kernel version: $kernel_version"
		fi
		rootfs_version=$(fdtget "$rootfs_file" /configurations/rootfs-conf version 2>/dev/null)
		if [ $? -ne 0 ]; then
			echo "$1 rootfs version: ERROR (fdtget failed for $rootfs_file)"
		else
			echo "$1 rootfs version: $rootfs_version"
		fi
	else
		echo "$1 bank tmp is empty."
	fi
}

unmount_filesystems() {
	umount /tmp/kernel_$1
	rmdir /tmp/kernel_$1
}

check_bank $bank