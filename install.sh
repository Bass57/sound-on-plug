#!/bin/bash

# Installs the companion hook and the systemd user service for Sound on Plug.
# Must be run from the plugin repository root (or via $PLUGIN_DIR below).
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
DST_HOOKS="$HOME/.config/omarchy/hooks"
DST_UNITS="$HOME/.config/systemd/user"

if [[ ! -f "$PLUGIN_DIR/hooks/plug-monitor.sh" ]]; then
  echo "error: run this script from the plugin repository root" >&2
  exit 1
fi

mkdir -p "$DST_HOOKS" "$DST_UNITS"
install -m 755 "$PLUGIN_DIR/hooks/sound-on-plug"    "$DST_HOOKS/sound-on-plug"
install -m 755 "$PLUGIN_DIR/hooks/plug-monitor.sh"  "$DST_HOOKS/plug-monitor.sh"
install -m 644 "$PLUGIN_DIR/systemd/sound-on-plug.service" "$DST_UNITS/sound-on-plug.service"

systemctl --user daemon-reload
systemctl --user enable --now sound-on-plug.service

echo "Installed hook + service. The 🔌 icon now shows while USB storage is"
echo "connected and chimes on plug / unmount / unplug. Remove it with ./uninstall.sh"