import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "demper.webapps"

  property bool gmailRunning: false
  property bool whatsappRunning: false
  readonly property real webappGap: Style.space(9)
  readonly property real trailingGap: Style.space(9)

  implicitWidth: (gmailRunning ? gmailButton.implicitWidth : 0)
               + (whatsappRunning ? whatsappButton.implicitWidth : 0)
               + (gmailRunning && whatsappRunning ? webappGap : 0)
               + (gmailRunning || whatsappRunning ? trailingGap : 0)
  implicitHeight: Math.max(gmailButton.implicitHeight, whatsappButton.implicitHeight)

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function launch(command) {
    if (root.bar) root.bar.run(command)
  }

  Component.onCompleted: refresh()

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    command: ["bash", "-lc", "$HOME/.config/omarchy/bar/scripts/webapp-status.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var state = JSON.parse(String(text || "{}"))
          root.gmailRunning = state.gmail === true
          root.whatsappRunning = state.whatsapp === true
        } catch (error) {
          root.gmailRunning = false
          root.whatsappRunning = false
        }
      }
    }
  }

  Row {
    anchors.fill: parent
    spacing: root.webappGap

    BarIconButton {
      id: gmailButton
      bar: root.bar
      text: "󰊫"
      slotSize: Style.bar.statusSlot
      opticalSize: Style.bar.iconCanvas
      fixedWidth: root.gmailRunning ? Style.bar.statusSlot : 0
      tooltipText: "Gmail"
      onPressed: function(button) {
        if (button === Qt.LeftButton) root.launch("~/.config/hypr/scripts/launch-or-focus-pwa-gmail.sh")
      }
    }

    BarIconButton {
      id: whatsappButton
      bar: root.bar
      text: "󰖣"
      slotSize: Style.bar.statusSlot
      opticalSize: Style.bar.iconCanvas
      fixedWidth: root.whatsappRunning ? Style.bar.statusSlot : 0
      tooltipText: "WhatsApp"
      onPressed: function(button) {
        if (button === Qt.LeftButton) root.launch("~/.config/hypr/scripts/launch-or-focus-pwa-whatsapp.sh")
      }
    }
  }
}
