#!/bin/bash

# Check for exactly 2 arguments
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <path to rbe image> <path to totalimage>"
  exit 1
fi

rbe="$1"
totalimage="$2"

# Ensure files exist
if [ ! -f "$rbe" ] || [ ! -f "$totalimage" ]; then
  echo "Error: Input file does not exist"
  exit 1
fi

echo "Current partion layout"
partx -s /dev/mmcblk0

# Backup calibration files from mmcblk0p14 using dd
echo "Backing up calibration files from /dev/mmcblk0p14..."
BACKUP_FILE="/tmp/calibration_backup.img"

# Mount the partition to get actual used space
MOUNT_P14="/tmp/mount_p14"
mkdir -p "$MOUNT_P14"

if mount /dev/mmcblk0p14 "$MOUNT_P14" 2>/dev/null; then
  echo "Mounted /dev/mmcblk0p14 successfully"
  
  # Get used space in bytes using du
  USED_SPACE=$(du -sb "$MOUNT_P14" | cut -f1)
  # Add small padding but don't exceed 2M
  BACKUP_SIZE=$((USED_SPACE + 65536))  # Add 64KB padding
  MAX_SIZE=$((2 * 1024 * 1024))  # 2MB in bytes
  
  if [ "$BACKUP_SIZE" -gt "$MAX_SIZE" ]; then
    BACKUP_SIZE=$MAX_SIZE
  fi
  
  echo "Used space: $USED_SPACE bytes"
  echo "Backup size with padding: $BACKUP_SIZE bytes"
  
  umount "$MOUNT_P14"
  
  # Backup only the required size
  if dd if=/dev/mmcblk0p14 of="$BACKUP_FILE" bs=1 count="$MAX_SIZE"; then
    echo "Calibration partition backed up to $BACKUP_FILE ($BACKUP_SIZE bytes)"
  else
    echo "Warning: Could not backup /dev/mmcblk0p14, proceeding without backup"
    BACKUP_FILE=""
  fi
else
  echo "Warning: Could not mount /dev/mmcblk0p14, proceeding without backup"
  BACKUP_FILE=""
fi

# Clean up mount point
rm -rf "$MOUNT_P14"

# Backup mfgdata
echo "Backing up mfgdata from /dev/mmcblk0p9..."
MFG_BACKUP_FILE="/tmp/mfgdata_backup.img"
mfg_block_size=$(cat /sys/block/mmcblk0/mmcblk0p9/size)

 if dd if=/dev/mmcblk0p9 of="$MFG_BACKUP_FILE" bs=512 count="$mfg_block_size"; then
   echo "mfgdata backed up to $MFG_BACKUP_FILE"
 else
   echo "Warning: Could not backup /dev/mmcblk0p9, proceeding without backup"
 fi


# Disable read-only mode for mmcblk0boot0
if ! echo 0 > /sys/block/mmcblk0boot0/force_ro; then
  echo "Error: Failed to disable read-only mode for mmcblk0boot0"
  exit 1
fi

# Get file sizes using du -b (GNU-specific)
if ! rbesize=$(du -b "$rbe" | cut -f1); then
  echo "Error: Failed to get size of $rbe"
  exit 1
fi

if ! totalimgsize=$(du -b "$totalimage" | cut -f1); then
  echo "Error: Failed to get size of $totalimage"
  exit 1
fi

rbesize_wohdr=$((rbesize - 64))
totalimgblksize=$((totalimgsize / 512))

echo "Size of rbe: $rbesize bytes"
echo "Size of rbe without header: $rbesize_wohdr bytes"
echo "Size of totalimage: $totalimgsize bytes"
echo "Size of totalimage block: $totalimgblksize bytes"

# Confirm before proceeding
read -p "Are you sure you want to write to /dev/mmcblk0boot0 and /dev/mmcblk0? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
  echo "Aborting."
  exit 1
fi

# Strip the header
echo "Striping header from rbe $rbe"
if ! dd if="$rbe" of="$rbe.wohdr" bs=1 count=$rbesize skip=64; then
  echo "Error: Failed to strip header from $rbe"
  exit 1
fi

if [ ! -f "$rbe.wohdr" ]; then
  echo "Error: $rbe.wohdr does not exist"
  exit 1
fi

# Write RBE "u-boot-spl-emmc1.bin" to "mmcblk0boot0"
echo "Writing '$rbe.wohdr' to 'mmcblk0boot0'"
if ! dd if="$rbe.wohdr" of=/dev/mmcblk0boot0 bs=1 count=$rbesize_wohdr; then
  echo "Error: Failed to write $rbe.wohdr to /dev/mmcblk0boot0"
  exit 1
fi

# Write total image to "mmcblk0"
echo "Writing '$totalimage' to 'mmcblk0'"
if ! dd if="$totalimage" of=/dev/mmcblk0 bs=512 count=$totalimgblksize ; then
  echo "Error: Failed to write $totalimage to /dev/mmcblk0"
  exit 1
fi

echo "Updated partion layout"
partx -s /dev/mmcblk0

# Wait for partitions to be recognized
sleep 5

# Stop services before partition operations
echo "Stopping lcm services..."
/etc/init.d/rlyeh stop
/etc/init.d/cthulhu stop
/etc/init.d/timingila stop

# Unmount all partitions
echo "Unmounting partitions..."
umount /dev/mmcblk0* 2>/dev/null

echo "Refreshing partition table..."
partx -d /dev/mmcblk0 >/dev/null 2>&1
partx -a /dev/mmcblk0 >/dev/null 2>&1

# Restore calibration files to mmcblk0p7 using format + dd
if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
  echo "Formatting /dev/mmcblk0p7 as ext2..."
  if mkfs.ext2 -F /dev/mmcblk0p7; then
    echo "Successfully formatted /dev/mmcblk0p8"

    echo "Restoring calibration files to /dev/mmcblk0p7..."
    if dd if="$BACKUP_FILE" of=/dev/mmcblk0p7 bs=1M; then
      echo "Calibration files restored to /dev/mmcblk0p7"
    else
      echo "Error: Could not restore calibration files to /dev/mmcblk0p7"
    fi
  else
    echo "Error: Failed to format /dev/mmcblk0p7"
  fi
else
  echo "No calibration backup to restore"
fi

# Restore mfgdata files to mmcblk0p13
if [ -n "$MFG_BACKUP_FILE" ] && [ -f "$MFG_BACKUP_FILE" ]; then
  echo "Restoring mfgdata files to /dev/mmcblk0p13..."
  if dd if="$MFG_BACKUP_FILE" of=/dev/mmcblk0p13 bs=2M; then
    echo "Successfully restored mfgdata"
  else
    echo "Error: Could not restore mfgdata to /dev/mmcblk0p13"
  fi
else
  echo "No mfgdata backup to restore"
fi

# Cleanup
rm -f "$BACKUP_FILE" "$MFG_BACKUP_FILE" "$rbe.wohdr"

# Reboot the system
echo "factoryreset the system..."
factoryreset
