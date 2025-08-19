#!/bin/sh
# shellcheck shell=dash

log() {
    [ -n "$DEBUG" ] && echo "[sfp_change] $*" && return
    logger "[sfp_change] $*"
}

_exit() {
    log "Exit with $1"
    case "$1" in
        "SUCCESS")
            echo "SUCCESS"
            exit 0
        ;;
        "NOT_SUPPORTED")
            echo "NOT_SUPPORTED"
            exit 1
        ;;
        "REBOOT_SYSTEM")
            echo "REBOOT_SYSTEM"
            # change to "2" when supported by SFP Manager
            exit 0
        ;;
        *)
            # try if param is a number,
            # if not the script will anyway stop with error
            exit "$1"
        ;;
    esac
}

if [ -n "$DEBUG" ]; then
    # simple emulation for debugging
    fw_printenv() {
        [ "$1" = "-n" ] && shift
        cat "$1"
    }
    fw_setenv() {
        echo "$2" > "$1"
    }
fi

get_image_mode() {
    fw_printenv -n wantype
}

set_image_mode() {
    log "Set new image mode $1"
    fw_setenv wantype "$1"
}

sfp_type=$1

case "$sfp_type" in
    "SFP_GPON" | "SFP_XGSPON")
        case "$(get_image_mode)" in
            pon*)
                log "Already PON, reboot to init again"
                # future enhancement can check here if reactivation without reboot might be possible
                _exit REBOOT_SYSTEM  #may be SUCCESS in future
            ;;
            *)
                log "Switch to PON"
                set_image_mode pon
                _exit REBOOT_SYSTEM
            ;;
        esac
    ;;
    "SFP_COPPER" | "SFP_AE")
        case "$(get_image_mode)" in
            eth*)
                log "Already ETH, no reboot"
                _exit SUCCESS
            ;;
            *)
                log "Switch to ETH"
                set_image_mode eth
                _exit REBOOT_SYSTEM
            ;;
        esac
    ;;
    "SFP_UNKNOWN")
        log "Type of SFP not known, no automatic switching"
        _exit NOT_SUPPORTED
    ;;
    *)
        log "Invalid argument $sfp_type"
        log "Accepted values: SFP_COPPER, SFP_AE, SFP_GPON, SFP_XGSPON, SFP_UNKNOWN"
        _exit NOT_SUPPORTED
    ;;
esac
