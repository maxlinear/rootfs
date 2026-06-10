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
            exit 2
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
    if [ "$action" = "REQUEST" ]; then
        fw_setenv wantype "$1"
        return
    fi

    if [ "$action" = "TEST" ]; then
        log "Dry run: would set image mode to $1"
        return
    fi

    log "Invalid action $action"
    _exit NOT_SUPPORTED
}

physical_type_old=$1
sfp_type_old=$2
extra_old=$3
physical_type_new=$4
sfp_type_new=$5
extra_new=$6
action=$7

if [ "$#" -ne 7 ]; then
    log "Invalid number of arguments: $#"
    log "Expected: <physical_type_old> <sfp_type_old> <extra_old> <physical_type_new> <sfp_type_new> <extra_new> <action>"
    _exit NOT_SUPPORTED
fi

case "$action" in
    "TEST" | "REQUEST")
        :
    ;;
    *)
        log "Invalid action $action"
        log "Accepted values: TEST, REQUEST"
        _exit NOT_SUPPORTED
    ;;
esac

log "Transition: ${physical_type_old}/${sfp_type_old}/${extra_old} -> ${physical_type_new}/${sfp_type_new}/${extra_new}, action=${action}"

mode_target=

case "$physical_type_new" in
    "GPON")
        mode_target=pon
    ;;
    "Ethernet")
        mode_target=eth
    ;;
    "SFP")
        case "$sfp_type_new" in
            "SFP_GPON" | "SFP_XGPON" | "SFP_NGPON2" | "SFP_XGSPON")
                mode_target=pon
            ;;
            "SFP_OPTICAL_ETHERNET" | "SFP_ELECTRICAL_ETHERNET")
                mode_target=eth
            ;;
            "SFP_MOCA" | "SFP_EPON" | "SFP_UNSUPPORTED")
                log "Unsupported SFP type $sfp_type_new for automatic switching"
                _exit NOT_SUPPORTED
            ;;
            *)
                log "Invalid SFP type $sfp_type_new"
                _exit NOT_SUPPORTED
            ;;
        esac
    ;;
    "ADSL" | "VDSL" | "GFAST" | "Bridge" | "WWAN")
        # TODO: Define expected image mode mapping for non-Ethernet/non-PON types.
        log "Unsupported physical type $physical_type_new for automatic switching"
        _exit SUCCESS
    ;;
    *)
        log "Invalid physical type $physical_type_new"
        _exit SUCCESS
    ;;
esac

case "$mode_target" in
    pon)
        case "$(get_image_mode)" in
            pon*)
                if [ -x /lib/pon/pon-is-same-sfp.sh ]; then
                    if /lib/pon/pon-is-same-sfp.sh; then
                        log "Already PON and same SFP, no reboot"
                        _exit SUCCESS
                    fi
                fi

                log "Already PON, reboot to init again"
                # future enhancement can check here if reactivation without reboot might be possible
                _exit REBOOT_SYSTEM
            ;;
            *)
                log "Switch to PON"
                set_image_mode pon
                _exit REBOOT_SYSTEM
            ;;
        esac
    ;;
    eth)
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
    *)
        log "Internal error: unsupported target mode $mode_target"
        _exit NOT_SUPPORTED
    ;;
esac
