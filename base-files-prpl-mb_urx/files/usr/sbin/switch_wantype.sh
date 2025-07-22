#!/bin/sh

# Check if wantype is provided as an argument in the correct format
if [ -z "$1" ] || ! echo "$1" | grep -qE '^wantype=(eth|pon)$'; then
    echo "Usage: $0 wantype=<eth|pon>"
    exit 1
fi

new_wantype=$(echo $1 | awk -F'=' '{print $2}')

current_wantype=$(fw_printenv -n wantype)

if [ "$new_wantype" = "$current_wantype" ]; then
	echo "The current WAN type and the WAN type passed to the script are the same!"
	echo -e "Wan type: $current_wantype\n"
	exit 1
fi

echo -e "\ncurrent Wan type: $current_wantype\nswitching to Wan type: $new_wantype\n"

fw_setenv wantype $new_wantype

VlanTerminationNumberOfEntries=$(ubus call Ethernet _get | grep -o '"VLANTerminationNumberOfEntries": [^,]*' | awk -F': ' '{print $2}')

if [ "$VlanTerminationNumberOfEntries" -gt 0 ]; then
	echo -e "Disabling $current_wantype wan configurations.\n"

	for i in $(seq 1 $VlanTerminationNumberOfEntries); do
		ubus-cli Ethernet.VLANTermination.$i.-
		sleep 1
	done

	ubus-cli WANManager.WANMode="demo_wanmode"
	sleep 5
	ubus-cli Device.IP.Interface.2.LowerLayers="Device.Ethernet.Link.2."
fi

rm -rf /etc/config/ppa

if [ "$new_wantype" = "pon" ]; then
	sed -i '/"wan": {/,/}/s/"device": "[^"]*"/"device": "VANI0"/' /etc/board.json
fi

if [ "$new_wantype" = "eth" ]; then
	sed -i '/"wan": {/,/}/s/"device": "[^"]*"/"device": "eth1"/' /etc/board.json
fi

echo "Rebooting the board"
reboot
