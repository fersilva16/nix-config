// One compact widget for every metric, in SystemMonitor's style: CPU usage,
// CPU temp and RAM come from noctalia's SystemStatService; GPU usage and VRAM
// from Main.qml. Left click: history panel. Middle click: external monitor.
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.System
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property var gpu: pluginApi?.mainInstance ?? null

  readonly property string screenName: screen ? screen.name : ""
  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"
  readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)

  readonly property real iconSize: Style.toOdd(capsuleHeight * 0.48)
  readonly property real gaugeThickness: Math.max(3, Style.toOdd(iconSize * 0.25))
  readonly property bool vramCritical: (gpu?.vramPercent ?? 0) >= SystemStatService.memCriticalThreshold

  readonly property real contentWidth: isVertical ? capsuleHeight : Math.round(metrics.implicitWidth + Style.margin2M)
  readonly property real contentHeight: isVertical ? Math.round(metrics.implicitHeight + Style.margin2M) : capsuleHeight

  implicitWidth: contentWidth
  implicitHeight: contentHeight

  Component.onCompleted: SystemStatService.registerComponent("plugin-sysmon:" + screenName)
  Component.onDestruction: SystemStatService.unregisterComponent("plugin-sysmon:" + screenName)

  function tooltipRows() {
    const s = SystemStatService;
    let rows = [["CPU", `${Math.round(s.cpuUsage)}% (${s.cpuFreq.replace(/[^0-9.]/g, "")} GHz)`]];
    if (s.cpuTemp > 0)
      rows.push(["CPU temp", `${Math.round(s.cpuTemp)}°C`]);
    rows.push(["Memory", `${Math.round(s.memPercent)}% (${s.memGb.toFixed(1)} GiB)`]);
    if (gpu?.available) {
      rows.push(["GPU", `${Math.round(gpu.usage)}%`]);
      rows.push(["VRAM", `${(gpu.vramUsedMib / 1024).toFixed(1)} / ${(gpu.vramTotalMib / 1024).toFixed(1)} GiB`]);
      rows.push(["GPU temp", `${Math.round(gpu.temp)}°C`]);
      rows.push(["GPU power", `${Math.round(gpu.power)} W`]);
    }
    return rows;
  }

  Rectangle {
    width: root.contentWidth
    height: root.contentHeight
    anchors.centerIn: parent
    radius: Style.radiusM
    color: Style.capsuleColor
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    GridLayout {
      id: metrics
      anchors.centerIn: parent
      flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
      rows: isVertical ? -1 : 1
      columns: isVertical ? 1 : -1
      rowSpacing: Style.marginL
      columnSpacing: Style.marginM

      Metric {
        vertical: root.isVertical
        iconSize: root.iconSize
        gaugeThickness: root.gaugeThickness
        icon: "cpu-usage"
        iconColor: (SystemStatService.cpuWarning || SystemStatService.cpuCritical) ? SystemStatService.cpuColor : Color.mOnSurface
        ratio: SystemStatService.cpuUsage / 100
        fill: SystemStatService.cpuColor
      }

      Metric {
        vertical: root.isVertical
        iconSize: root.iconSize
        gaugeThickness: root.gaugeThickness
        icon: "cpu-temperature"
        iconColor: (SystemStatService.tempWarning || SystemStatService.tempCritical) ? SystemStatService.tempColor : Color.mOnSurface
        ratio: SystemStatService.cpuTemp / 100
        fill: SystemStatService.tempColor
      }

      Metric {
        vertical: root.isVertical
        iconSize: root.iconSize
        gaugeThickness: root.gaugeThickness
        icon: "memory"
        iconColor: (SystemStatService.memWarning || SystemStatService.memCritical) ? SystemStatService.memColor : Color.mOnSurface
        ratio: SystemStatService.memPercent / 100
        fill: SystemStatService.memColor
      }

      // GPU usage + VRAM
      Metric {
        visible: gpu?.available ?? false
        vertical: root.isVertical
        iconSize: root.iconSize
        gaugeThickness: root.gaugeThickness
        icon: "gpu-temperature"
        ratio: (gpu?.usage ?? 0) / 100
        ratio2: (gpu?.vramPercent ?? 0) / 100
        fill2: root.vramCritical ? Color.mError : Color.mPrimary
      }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    hoverEnabled: true
    onClicked: mouse => {
                 TooltipService.hide();
                 if (mouse.button === Qt.MiddleButton)
                   Quickshell.execDetached(["sh", "-c", Settings.data.systemMonitor.externalMonitor]);
                 else
                   pluginApi?.togglePanel(root.screen, root);
               }
    onEntered: {
      TooltipService.show(root, tooltipRows(), BarService.getTooltipDirection(root.screenName));
      tooltipRefresh.start();
    }
    onExited: {
      tooltipRefresh.stop();
      TooltipService.hide();
    }
  }

  Timer {
    id: tooltipRefresh
    interval: 1000
    repeat: true
    onTriggered: TooltipService.updateText(tooltipRows())
  }
}
