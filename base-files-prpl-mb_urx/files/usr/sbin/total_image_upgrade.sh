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

# Factory reset the system
echo "Factory resetting the system..."
factoryreset
