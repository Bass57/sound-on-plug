# 🔌 Sound on Plug

Chill chimes and a custom status-bar icon for USB connect and disconnect events
on Omarchy (Wayland / Hyprland / Quickshell).

- **plug** (USB device connected) → `plug.wav`, icon appears
- **unmount** (USB filesystem ejected) → `inject.wav`
- **unplug** (USB device removed) → `unplug.wav`, icon hides when none remain

Detection is fully **user-space** — no root, no `sudo`, no udev rules:
`udevadm monitor` (USB events) + `gdbus monitor` (UDisks2 `MountPoints`
changes) run in a normal systemd **user** service. USB root hubs and interface
events are ignored; USB peripherals and storage devices are supported.

## Install

```sh
omarchy plugin add https://github.com/Bass57/sound-on-plug.git --enable
~/.config/omarchy/plugins/io.github.bass57.sound-on-plug/install.sh
omarchy restart shell
```

The plugin itself is the bar icon. The `install.sh` step deploys the two
companion pieces needed to actually hear/see events:

- `~/.config/omarchy/hooks/sound-on-plug` — plays the matching sound
- `~/.config/omarchy/hooks/plug-monitor.sh` — the event daemon
- `~/.config/systemd/user/sound-on-plug.service` — runs the daemon

The installer copies these companion files; the icon and sounds remain in
the plugin directory.

## Usage

| Action | Result |
|--------|--------|
| Plug in a USB device | `plug` chime, custom icon appears |
| Eject/unmount the drive | `inject` chime |
| Unplug the device | `unplug` chime; icon hides when none remain |
| Click icon (left / middle / right) | Preview plug / inject / unplug |

Sounds are intentionally short. Playback uses `pw-play` from PipeWire.

## Verify

```sh
systemctl --user status sound-on-plug   # running?
```

The bar icon starts with the current USB-device state and then updates on
device add/remove events.

## Uninstall

```sh
~/.config/omarchy/plugins/io.github.bass57.sound-on-plug/uninstall.sh
omarchy plugin remove io.github.bass57.sound-on-plug
```

## Dependencies

- `udevadm` (systemd)
- `gdbus` (glib2)
- `notify-send` (libnotify)
- `pw-play` (PipeWire)
- a systemd user session (`graphical-session.target`)

Regenerating the sounds (all synthesized, no samples):

```sh
scripts/gen-sounds.sh   # needs ffmpeg + python3
```

## Notes

- The 2-second cooldown guarantees exactly **one** chime per physical
  action, even when eject and removal happen back-to-back.
- Only `UDEV` (post-rules) events are consumed; `KERNEL` mirror events are
  ignored, and duplicate events within two seconds are suppressed.
- The daemon detects a real unmount from the udisks2 Filesystem object's
  `MountPoints` changing to empty — udisks2 emits no `Unmounted` signal, and
  `dbus-monitor` is unusable on hardened buses, so `gdbus` is used instead.

## Security / Trust

The marketplace validates listings, **not** behavior. This plugin runs
unsandboxed, like all Omarchy shell plugins. Review the effort you trust: the
manifest, `BarWidget.qml`, the two hooks, and `install.sh` are small and
self-contained. It does not modify your configuration except for the three
files listed above (undoable via `uninstall.sh`).

## License

MIT — see [`LICENSE`](LICENSE). All audio is synthesized at build time by
`scripts/gen-sounds.sh`; no third-party samples are distributed.