#!/bin/sh

# Help message
show_help() {
  echo "Usage: $0 [OPTIONS] MODE"
  echo "OPTIONS:"
  echo "  -h, --help      Show help output."
  echo "MODE:"
  echo "  ax              Configure in ax mode"
  echo "  be              Configure in be mode"
  echo "Description:"
  echo "  Configures operating standard as specified (ax/be) and respective wpa security profiles for 2G, 5G radio"
}

# Check for help option
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  show_help
  exit 0
fi

# Check if exactly one argument is passed
if [ "$#" -ne 1 ]; then
  show_help
  exit 1
fi

mode="$1"

# Validate input
if [ "$mode" != "ax" ] && [ "$mode" != "be" ]; then
  echo "Error: Invalid input. Please enter 'ax' or 'be'."
  show_help
  exit 1
fi

# Set security mode based on mode
if [ "$mode" = "be" ]; then
  security_mode="WPA2-WPA3-Personal"
elif [ "$mode" = "ax" ]; then
  security_mode="WPA2-Personal"
fi

# Apply security mode to all VAPs in 2G/5G radio
totalVaps=$(($(ubus call WiFi.AccessPoint _get | grep 'WiFi.AccessPoint.' | wc -l) - 1))

for intf in $(seq 1 $totalVaps); do
  radio=$(ubus call WiFi.AccessPoint.$intf _get | grep 'RadioReference' | sed -n 's/.*radio\([0-9]*\).*/\1/p')
  if [ "$radio" = "0" ] || [ "$radio" = "2" ]; then
    echo "Setting $security_mode on AccessPoint $intf..."
    ubus call WiFi.AccessPoint.$intf.Security _set "{\"parameters\": {\"ModeEnabled\":\"$security_mode\"}}"
  fi
done

# Set operating standard for all 3 radios
for rad in $(seq 1 3); do
  echo "Setting OperatingStandard to $mode on Radio $rad..."
  ubus call WiFi.Radio.$rad _set "{\"parameters\": {\"OperatingStandards\": \"$mode\"}}"
done

echo "Configuration complete."