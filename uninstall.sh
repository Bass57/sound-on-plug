#!/bin/bash

# Removes the companion hook and systemd user service for Sound on Plug.
set -euo pipefail

systemctl --user disable --now sound-on-plug.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/sound-on-plug.service"
rm -f "$HOME/.config/omarchy/hooks/sound-on-plug"
rm -f "$HOME/.config/omarchy/hooks/plug-monitor.sh"
rm -f "$HOME/.local/state/omarchy/sound-on-plug-status"
rm -f "$HOME/.local/state/omarchy/plug-monitor.log"
rm -f "$HOME/.local/state/omarchy/sound-on-plug.log"
systemctl --user daemon-reload

echo "Removed hook + service. Remove the bar widget itself with:" 
echo "  omarchy plugin remove io.github.bass57.sound-on-plug"