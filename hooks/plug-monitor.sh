#!/usr/bin/env bash
set -uo pipefail

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
status_file="$state_dir/sound-on-plug-status"
sound_hook="$HOME/.config/omarchy/hooks/sound-on-plug"

mkdir -p "$state_dir"

write_status() {
  local value="$1"
  local temporary_file
  temporary_file="$(mktemp "$state_dir/sound-on-plug-status.XXXXXX")"
  printf '%s\n' "$value" > "$temporary_file"
  mv -f "$temporary_file" "$status_file"
}

declare -A connected_devices=()

set_status_from_events() {
  if (( ${#connected_devices[@]} > 0 )); then
    write_status 1
  else
    write_status 0
  fi
}

initialize_connected_devices() {
  local vendor_file device_dir device_name
  shopt -s nullglob
  for vendor_file in /sys/bus/usb/devices/*/idVendor; do
    device_dir="${vendor_file%/idVendor}"
    device_name="${device_dir##*/}"
    [[ "$device_name" =~ ^[0-9]+-[0-9]+(\.[0-9]+)*$ ]] || continue
    [[ -r "$device_dir/idProduct" ]] || continue
    connected_devices["$device_name"]=1
  done
  set_status_from_events
}

handle_event() {
  local action="$1"
  local device_path="$2"
  local model="$3"
  local sound title body

  case "$action" in
    add)
      sound=plug
      title="USB device connected"
      ;;
    remove)
      sound=unplug
      title="USB device disconnected"
      sleep 0.2
      ;;
    *)
      return 0
      ;;
  esac

  model="${model//_/ }"
  body="${model:-${device_path##*/}}"

  if [[ "$action" == add ]]; then
    connected_devices["${device_path##*/}"]=1
  else
    unset "connected_devices[${device_path##*/}]"
  fi
  set_status_from_events

  if ! "$sound_hook" "$sound"; then
    printf 'Failed to play USB %s sound for %s\n' "$sound" "$device_path" >&2
  fi
  if ! /usr/bin/notify-send --app-name="Omarchy USB" "$title" "$body"; then
    printf 'Failed to send USB %s notification for %s\n' "$action" "$device_path" >&2
  fi
}

process_record() {
  [[ -n "$action" && "$device_type" == usb_device && -n "$device_path" ]] || return 0
  [[ "${device_path##*/}" =~ ^usb[0-9]+$ ]] && return 0
  handle_event "$action" "$device_path" "${database_model:-$model}"
}

watch_usb_unmounts() {
  local line object_path block_name sysfs_path

  while true; do
    while IFS= read -r line; do
      [[ "$line" == *"org.freedesktop.DBus.Properties.PropertiesChanged"* ]] || continue
      [[ "$line" == *"org.freedesktop.UDisks2.Filesystem"* ]] || continue
      [[ "$line" == *"MountPoints"* && "$line" == *"@aay []"* ]] || continue

      object_path="${line%%:*}"
      block_name="${object_path##*/}"
      [[ "$block_name" =~ ^[[:alnum:]_]+$ ]] || continue
      [[ -e "/sys/class/block/$block_name/device" ]] || continue
      sysfs_path="$(readlink -f "/sys/class/block/$block_name/device")" || continue
      [[ "$sysfs_path" =~ /usb[0-9]+/[0-9]+-[0-9]+ ]] || continue

      if ! "$sound_hook" inject; then
        printf 'Failed to play USB inject sound for %s\n' "$block_name" >&2
      fi
    done < <(/usr/bin/gdbus monitor --system --dest org.freedesktop.UDisks2)

    printf 'UDisks2 monitor exited; retrying in 5 seconds\n' >&2
    sleep 5
  done
}

initialize_connected_devices

action=""
device_type=""
device_path=""
model=""
database_model=""

watch_usb_unmounts &

while IFS= read -r line; do
  case "$line" in
    UDEV\ *)
      process_record
      action=""
      device_type=""
      device_path=""
      model=""
      database_model=""
      read -r _ _ action device_path _ <<< "$line"
      ;;
    ACTION=*)
      action="${line#ACTION=}"
      ;;
    DEVTYPE=*)
      device_type="${line#DEVTYPE=}"
      ;;
    ID_MODEL_FROM_DATABASE=*)
      database_model="${line#ID_MODEL_FROM_DATABASE=}"
      ;;
    ID_MODEL=*)
      model="${line#ID_MODEL=}"
      ;;
    "")
      process_record
      action=""
      device_type=""
      device_path=""
      model=""
      database_model=""
      ;;
  esac
done < <(/usr/bin/udevadm monitor --udev --property --subsystem-match=usb)

printf 'udevadm monitor exited unexpectedly\n' >&2
exit 1
