#!/bin/bash

# User-space daemon: plays a single chime per physical USB action and tracks
# bar-icon visibility. No root required.
#   plug    - usb subsystem device attach             -> plug.wav   (+ show icon)
#   unmount - UDisks2 MountPoints -> empty (USB)      -> inject.wav
#   unplug  - usb subsystem device detach             -> unplug.wav (- hide icon)
#
# Notes:
#   * udev: only "device level" usb events are used (no root hubs/interface
#     tails), and only UDEV (post-rules) headers -> KERNEL mirrors ignored.
#   * udisks2 emits NO Filesystem.Unmounted signal; unmount is detected via
#     Properties.PropertiesChanged on the Filesystem interface when its
#     MountPoints array becomes empty (gdbus monitor, standard subscription).
#   * dbus-monitor is intentionally not used: on some systems it gets
#     "not authorized to send message" and silently receives nothing.
#   * A file-based 2s cooldown shared across both watchers guarantees exactly
#     one sound per physical action (e.g. eject -> inject, then pull -> unplug
#     is suppressed).
#
# Dependencies: udevadm (systemd), gdbus (glib2), stdbuf (coreutils),
#               lsblk (util-linux), and the sound-on-plug hook.

LOG_FILE="$HOME/.local/state/omarchy/plug-monitor.log"
STATUS_FILE="$HOME/.local/state/omarchy/sound-on-plug-status"
LAST_FILE="$HOME/.local/state/omarchy/sound-on-plug-last"
mkdir -p "$(dirname "$LOG_FILE")"

echo "$(date '+%F %T'): plug-monitor starting" >> "$LOG_FILE"

cooldown_ok() {
  local now last
  now="$(date +%s)"
  last="$(cat "$LAST_FILE" 2>/dev/null || echo 0)"
  if (( now - last < 2 )); then
    echo "$(date '+%F %T'): cooldown: suppressing sound (event: $1)" >> "$LOG_FILE"
    return 1
  fi
  printf '%s\n' "$now" > "$LAST_FILE"
  return 0
}

hook() { "$HOME/.config/omarchy/hooks/sound-on-plug" "$1" >>"$LOG_FILE" 2>&1; }

# --------------------------------------------------------------------------
# Bar-icon visibility state: the plugin watches this file and hides when it
# reads "0" (no USB storage connected). plug -> 1, unplug -> 0 (or 1 if
# another USB storage device is still present).
# --------------------------------------------------------------------------
update_status() {
  local value="$1"
  printf '%s\n' "$value" > "$STATUS_FILE"
  echo "$(date '+%F %T'): status -> $value" >> "$LOG_FILE"
}

# Bar icon = USB *storage* is physically connected. Mice/keyboards/dongles must
# not keep the icon alive; only devices exposing a USB block device (usb-storage
# or uas) do. Re-evaluated from sysfs on every event, so it reflects reality.
connected_usb_visible() {
  /usr/bin/lsblk -d -n -o TRAN 2>/dev/null | grep -q '^usb$'
}

refresh_status() {
  if connected_usb_visible; then
    update_status 1
  else
    update_status 0
  fi
}

# --------------------------------------------------------------------------
# USB udev watcher -> plug/unplug (device-level events only)
# --------------------------------------------------------------------------
# Real udevadm output: `UDEV  [ts] ...` (two spaces) and `KERNEL[ts] ...` (none).
usb_watch() {
  stdbuf -oL udevadm monitor --subsystem-match=usb --property | while IFS= read -r line; do
    if [[ "$line" =~ ^UDEV[[:space:]]*\[ ]]; then
      current_action=""
      current_devpath=""
      active_header=udev
      continue
    fi
    if [[ "$line" =~ ^KERNEL[[:space:]]*\[ ]]; then
      current_action=""
      current_devpath=""
      active_header=skip
      continue
    fi
    [[ "$active_header" == "skip" ]] && continue
    case "$line" in
      ACTION=*)  current_action="${line#ACTION=}" ;;
      DEVPATH=*) current_devpath="${line#DEVPATH=}" ;;
    esac
    if [[ -z "$line" && -n "$current_action" ]]; then
      local devpath="$current_devpath"
      local action="$current_action"
      current_action=""
      current_devpath=""
      # Device-level only: skip root hubs (.../usbN) and interface tails
      # (a ':' component right behind the USB node, e.g. .../usb1/1-2:1.0).
      [[ -z "$devpath" ]] && continue
      [[ "$devpath" =~ /usb[0-9]+$ ]] && continue
      local tail="${devpath#*/usb[0-9]}"
      if [[ "$tail" != "$devpath" && "$tail" == *:* ]]; then continue; fi

      if [[ "$action" == "add" ]]; then
        if cooldown_ok plug; then hook plug; fi
        refresh_status
        echo "$(date '+%F %T'): plug: $devpath" >> "$LOG_FILE"
      elif [[ "$action" == "remove" ]]; then
        if cooldown_ok unplug; then hook unplug; fi
        refresh_status
        echo "$(date '+%F %T'): unplug: $devpath" >> "$LOG_FILE"
      fi
    fi
  done
}

# --------------------------------------------------------------------------
# UDisks2 unmount watcher -> inject (Filesystem MountPoints becomes empty)
# --------------------------------------------------------------------------
is_usb_block() {
  local dev="$1"
  [[ -z "$dev" ]] && return 1
  local props
  props="$(udevadm info -q property -n "/dev/$dev" 2>/dev/null)"
  if [[ -z "$props" ]]; then
    # Device already gone (e.g. stick pulled during unmount): assume removable.
    return 0
  fi
  grep -q '^ID_BUS=usb' <<<"$props" && return 0
  grep -q '^ID_USB_DRIVER=' <<<"$props" && return 0
  return 1
}
unmount_watch() {
  gdbus monitor --system --dest org.freedesktop.UDisks2 | while IFS= read -r line; do
    [[ "$line" != *"org.freedesktop.UDisks2.Filesystem"* ]] && continue
    [[ "$line" != *"PropertiesChanged"* ]] && continue
    [[ "$line" != *"MountPoints"* ]] && continue
    if [[ "$line" == *"'MountPoints': <@aay []>"* || "$line" == *"'MountPoints': <[]>"* ]]; then
      if [[ "$line" =~ /org/freedesktop/UDisks2/block_devices/([a-zA-Z0-9]+) ]]; then
        local dev="${BASH_REMATCH[1]}"
        if is_usb_block "$dev"; then
          if cooldown_ok inject; then hook inject; fi
          refresh_status
          echo "$(date '+%F %T'): unmount: $dev" >> "$LOG_FILE"
        else
          echo "$(date '+%F %T'): unmount (non-usb, skipped): $dev" >> "$LOG_FILE"
        fi
      fi
    fi
  done
}

# Initial bar-icon state: USB storage plugged in right now?
refresh_status

usb_watch &
unmount_watch &
wait