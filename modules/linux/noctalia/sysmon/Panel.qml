// Click-open panel, laid out like noctalia's built-in SystemStatsPanel:
// CPU (usage + temp), memory, GPU (usage + temp) and VRAM graph cards, then
// a details box.
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.System
import qs.Widgets

Item {
  id: root

  property var pluginApi: null
  readonly property var gpu: pluginApi?.mainInstance ?? null

  property real contentPreferredWidth: Math.round(440 * Style.uiScaleRatio)
  property real contentPreferredHeight: mainColumn.implicitHeight + Style.margin2L

  Component.onCompleted: SystemStatService.registerComponent("plugin-sysmon-panel")
  Component.onDestruction: SystemStatService.unregisterComponent("plugin-sysmon-panel")

  // Graph card: primary/secondary readouts, a label, and a 1- or 2-line graph.
  component Card: NBox {
    id: card
    property string primaryText
    property string secondaryText
    property string label
    property alias values: graph.values
    property alias values2: graph.values2
    property alias minValue2: graph.minValue2
    property alias maxValue2: graph.maxValue2
    property alias updateInterval: graph.updateInterval

    Layout.fillWidth: true
    Layout.preferredHeight: 90 * Style.uiScaleRatio

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginS
      anchors.bottomMargin: Style.radiusM * 0.5
      spacing: Style.marginXS

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginXS

        NText {
          text: card.primaryText
          pointSize: Style.fontSizeXS
          color: Color.mPrimary
          font.family: Settings.data.ui.fontFixed
          Layout.rightMargin: Style.marginS
        }

        NText {
          visible: card.secondaryText !== ""
          text: card.secondaryText
          pointSize: Style.fontSizeXS
          color: Color.mSecondary
          font.family: Settings.data.ui.fontFixed
        }

        Item {
          Layout.fillWidth: true
        }

        NText {
          text: card.label
          pointSize: Style.fontSizeXS
          color: Color.mOnSurfaceVariant
        }
      }

      NGraph {
        id: graph
        Layout.fillWidth: true
        Layout.fillHeight: true
        minValue: 0
        maxValue: 100
        color: Color.mPrimary
        color2: Color.mSecondary
        strokeWidth: Math.max(1, Style.uiScaleRatio)
        fill: true
        fillOpacity: 0.15
      }
    }
  }

  // Label/value row for the details box.
  component Detail: RowLayout {
    property string label
    property string value

    Layout.fillWidth: true
    spacing: Style.marginS

    NText {
      text: parent.label + ":"
      pointSize: Style.fontSizeXS
      color: Color.mOnSurfaceVariant
    }

    NText {
      text: parent.value
      pointSize: Style.fontSizeXS
      color: Color.mOnSurface
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignRight
    }
  }

  ColumnLayout {
    id: mainColumn
    anchors.fill: parent
    anchors.margins: Style.marginL
    spacing: Style.marginM

    NBox {
      Layout.fillWidth: true
      implicitHeight: headerRow.implicitHeight + Style.margin2M

      RowLayout {
        id: headerRow
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginM

        NIcon {
          icon: "device-analytics"
          pointSize: Style.fontSizeXXL
          color: Color.mPrimary
        }

        NText {
          text: "System monitor"
          pointSize: Style.fontSizeL
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
          Layout.fillWidth: true
        }

        NIconButton {
          icon: "close"
          baseSize: Style.baseWidgetSize * 0.8
          onClicked: pluginApi?.closePanel(pluginApi.panelOpenScreen)
        }
      }
    }

    Card {
      primaryText: `${Math.round(SystemStatService.cpuUsage)}% (${SystemStatService.cpuFreq.replace(/[^0-9.]/g, "")} GHz)`
      secondaryText: `${Math.round(SystemStatService.cpuTemp)}°C`
      label: "CPU"
      values: SystemStatService.cpuHistory
      values2: SystemStatService.cpuTempHistory
      minValue2: Math.max(SystemStatService.cpuTempHistoryMin - 5, 0)
      maxValue2: Math.max(SystemStatService.cpuTempHistoryMax + 5, 1)
      updateInterval: SystemStatService.cpuUsageIntervalMs
    }

    Card {
      primaryText: `${Math.round(SystemStatService.memPercent)}% (${SystemStatService.memGb.toFixed(1)} GiB)`
      label: "Memory"
      values: SystemStatService.memHistory
      updateInterval: SystemStatService.memIntervalMs
    }

    Card {
      visible: gpu?.available ?? false
      primaryText: `${Math.round(gpu?.usage ?? 0)}%`
      secondaryText: `${Math.round(gpu?.temp ?? 0)}°C`
      label: "GPU"
      values: gpu?.usageHistory ?? []
      values2: gpu?.tempHistory ?? []
      minValue2: 20
      maxValue2: 100
      updateInterval: gpu?.intervalMs ?? 2000
    }

    Card {
      visible: gpu?.available ?? false
      primaryText: `${Math.round(gpu?.vramPercent ?? 0)}% (${((gpu?.vramUsedMib ?? 0) / 1024).toFixed(1)} GiB)`
      label: "VRAM"
      values: gpu?.vramHistory ?? []
      updateInterval: gpu?.intervalMs ?? 2000
    }

    NBox {
      Layout.fillWidth: true
      implicitHeight: details.implicitHeight + Style.margin2M

      ColumnLayout {
        id: details
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.marginM
        spacing: Style.marginXS

        Detail {
          label: "Load average"
          value: `${SystemStatService.loadAvg1.toFixed(2)} • ${SystemStatService.loadAvg5.toFixed(2)} • ${SystemStatService.loadAvg15.toFixed(2)}`
        }

        Detail {
          label: "Disk"
          value: `${SystemStatService.diskPercents["/"] || 0}% (${(SystemStatService.diskUsedGb["/"] || 0).toFixed(1)} / ${(SystemStatService.diskSizeGb["/"] || 0).toFixed(1)} GB)`
        }

        Detail {
          visible: gpu?.available ?? false
          label: gpu?.name ?? "GPU"
          value: `${((gpu?.vramUsedMib ?? 0) / 1024).toFixed(1)} / ${((gpu?.vramTotalMib ?? 0) / 1024).toFixed(1)} GiB, ${Math.round(gpu?.power ?? 0)} / ${Math.round(gpu?.powerLimit ?? 0)} W`
        }
      }
    }
  }
}
