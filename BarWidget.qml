import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.bass57.sound-on-plug"

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string hookPath: home + "/.config/omarchy/hooks/sound-on-plug"
  readonly property string stateFilePath: home + "/.local/state/omarchy/sound-on-plug-status"

  // Hidden while "0": no USB storage connected, or none plugged. The
  // plug-monitor daemon (./install.sh) rewrites this file on every event.
  property bool usbPresent: true

  visible: root.usbPresent

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  FileView {
    id: stateFile
    path: root.stateFilePath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.usbPresent = String(text()).trim() === "1"
    }
    onFileChanged: reload()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "🔌"
    fontFamily: ""
    horizontalMargin: 7.5
    tooltipText: "Left: plug · Right: unplug · Middle: unmount"
    onPressed: function(button) {
      if (!root.bar || !root.hookPath) return
      if (button === Qt.RightButton) {
        root.bar.run("bash \"" + root.hookPath + "\" unplug")
      } else if (button === Qt.MiddleButton) {
        root.bar.run("bash \"" + root.hookPath + "\" inject")
      } else {
        root.bar.run("bash \"" + root.hookPath + "\" plug")
      }
    }
  }
}