import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "demper.cpu"
  ipcTarget: "demper.cpu"

  property var stats: Model.emptyStats()

  readonly property bool hasStats: stats.model !== ""
  readonly property string profileName: stats.profile && stats.profile.name
    ? String(stats.profile.name) : ""

  function refresh() {
    if (!statsProc.running) statsProc.running = true
  }

  function updateStats(raw) {
    var next = Model.parseStats(raw)
    if (next) stats = next
  }

  function barText() {
    if (root.vertical) return "󰍛"
    return "󰍛 " + (root.hasStats ? Model.percent(root.stats.total) : "—")
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  Process {
    id: statsProc
    command: ["bash", "-lc", "$HOME/.config/omarchy/plugins/demper.cpu/stats.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateStats(text)
    }
  }

  Timer {
    interval: 2500
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText()
    slotSize: Style.bar.iconSlot * (root.vertical ? 1 : 2)
    tooltipText: root.hasStats
      ? "CPU " + Model.percent(root.stats.total) + " · Memory " + Model.percent(root.stats.memory.percent)
      : "CPU monitor"
    onPressed: function(buttonId) {
      if (buttonId === Qt.LeftButton) root.toggle()
    }
  }

  PopupCard {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: popup.fittedContentWidth(Style.space(430))
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight, Style.space(620))

    Column {
      id: contentColumn
      width: parent.width
      spacing: Style.space(12)

      Item {
        width: parent.width
        implicitHeight: Math.max(cpuIcon.implicitHeight, cpuLabels.implicitHeight, cpuPercent.implicitHeight)

        Text {
          id: cpuIcon
          text: "󰍛"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.display
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          id: cpuLabels
          anchors.left: cpuIcon.right
          anchors.leftMargin: Style.space(14)
          anchors.right: cpuPercent.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            text: "CPU monitor"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            text: root.stats.model || "Reading telemetry…"
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
          }
        }

        Text {
          id: cpuPercent
          text: root.hasStats ? Model.percent(root.stats.total) : "—"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.displayLarge
          font.bold: true
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Rectangle {
        width: parent.width
        height: Style.space(7)
        radius: height / 2
        color: Util.alpha(root.bar.foreground, 0.14)

        Rectangle {
          width: Math.max(height, parent.width * Math.min(1, Math.max(0, root.stats.total / 100)))
          height: parent.height
          radius: parent.radius
          color: root.bar.foreground
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(20)

        Column {
          width: (parent.width - parent.spacing) / 2
          spacing: Style.spacing.labelGap
          StatPair { label: "Memory"; value: Model.gigabytes(root.stats.memory.used) + " / " + Model.gigabytes(root.stats.memory.total) }
          StatPair { label: "Swap"; value: Model.gigabytes(root.stats.swap.used) + " / " + Model.gigabytes(root.stats.swap.total) }
          StatPair { label: "Load average"; value: root.stats.load.map(function(value) { return Number(value).toFixed(2) }).join("  ") }
        }

        Column {
          width: (parent.width - parent.spacing) / 2
          spacing: Style.spacing.labelGap
          StatPair { label: "CPU temperature"; value: root.stats.temperatures.length ? Model.temperature(root.stats.temperatures[0].value) : "—" }
          StatPair { label: "TUXEDO profile"; value: root.stats.profile.name || "—" }
          StatPair { label: "Uptime"; value: Model.uptime(root.stats.uptime) }
        }
      }

      PanelSeparator { foreground: root.bar.foreground }

      Column {
        width: parent.width
        spacing: Style.space(8)

        PanelSectionHeader {
          text: "PER-CORE LOAD"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Flickable {
          width: parent.width
          height: Math.min(Style.space(360), coreColumn.implicitHeight)
          implicitHeight: height
          contentWidth: width
          contentHeight: coreColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: coreColumn
            width: parent.width
            spacing: Style.space(3)

            Repeater {
              model: root.stats.cores

              delegate: Item {
                required property var modelData
                width: coreColumn.width
                height: Style.space(24)

                Text {
                  text: "C" + modelData.id + " " + Model.frequency(modelData.frequency)
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  width: Style.space(82)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                  id: coreTrack
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(86)
                  anchors.right: coreValue.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  height: Style.space(6)
                  radius: height / 2
                  color: Util.alpha(root.bar.foreground, 0.14)

                  Rectangle {
                    width: Math.max(height, parent.width * Math.min(1, Math.max(0, modelData.usage / 100)))
                    height: parent.height
                    radius: parent.radius
                    color: root.bar.foreground
                  }
                }

                Text {
                  id: coreValue
                  text: Model.percent(modelData.usage)
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  horizontalAlignment: Text.AlignRight
                  width: Style.space(42)
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }
        }
      }

      PanelSeparator { foreground: root.bar.foreground }

      Column {
        width: parent.width
        spacing: Style.space(6)

        PanelSectionHeader {
          text: "FREQUENCY · SENSORS · POWER"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        StatPair { label: "Driver"; value: root.stats.frequency.driver || "—" }
        StatPair { label: "TUXEDO profile"; value: root.profileName || "Unavailable" }

        Repeater {
          model: root.stats.temperatures
          delegate: StatPair {
            required property var modelData
            label: modelData.name
            value: Model.temperature(modelData.value)
          }
        }
      }
    }
  }

  component StatPair: Row {
    property string label: ""
    property string value: ""
    width: parent ? parent.width : 0
    spacing: Style.space(8)

    Text {
      text: label
      color: Qt.darker(root.bar.foreground, 1.4)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      width: Math.max(0, parent.width - valueText.width - parent.spacing)
    }

    Text {
      id: valueText
      text: value
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignRight
      width: Math.max(Style.space(50), implicitWidth)
    }
  }
}
