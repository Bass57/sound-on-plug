import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.bass57.sound-on-plug"

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string hookPath: home + "/.config/omarchy/hooks/sound-on-plug"
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
  readonly property string stateFilePath: stateHome + "/omarchy/sound-on-plug-status"

  // The companion monitor updates this file on USB add/remove events.
  property bool usbPresent: false

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
    text: " "
    labelVisible: false
    fixedWidth: 34
    tooltipText: "Left: plug · Middle: inject · Right: unplug sound preview"
    onPressed: function(button) {
      if (!root.bar || !root.hookPath) return
      if (button === Qt.LeftButton) {
        root.bar.run("bash \"" + root.hookPath + "\" plug")
      } else if (button === Qt.MiddleButton) {
        root.bar.run("bash \"" + root.hookPath + "\" inject")
      } else if (button === Qt.RightButton) {
        root.bar.run("bash \"" + root.hookPath + "\" unplug")
      }
    }

    Image {
      anchors.centerIn: parent
      width: 20
      height: 20
      source: Qt.resolvedUrl("usb-plug.svg")
      sourceSize.width: 40
      sourceSize.height: 40
      smooth: true
    }
  }
}