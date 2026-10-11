// Bar metric: icon followed by one or two mini gauges (SystemMonitor's
// compact look).
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

GridLayout {
  id: metric

  property bool vertical: false
  property real iconSize: 10
  property real gaugeThickness: 3
  property string icon
  property color iconColor: Color.mOnSurface
  property real ratio: 0
  property color fill: Color.mPrimary
  property real ratio2: -1 // < 0 hides the second gauge
  property color fill2: Color.mPrimary

  flow: vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
  rows: vertical ? -1 : 1
  columns: vertical ? 1 : -1
  rowSpacing: 3
  columnSpacing: 3
  Layout.alignment: Qt.AlignCenter

  NIcon {
    icon: metric.icon
    pointSize: metric.iconSize
    applyUiScale: false
    color: metric.iconColor
    Layout.alignment: Qt.AlignCenter
  }

  NLinearGauge {
    orientation: metric.vertical ? Qt.Horizontal : Qt.Vertical
    Layout.preferredWidth: metric.vertical ? metric.iconSize : metric.gaugeThickness
    Layout.preferredHeight: metric.vertical ? metric.gaugeThickness : metric.iconSize
    Layout.alignment: Qt.AlignCenter
    ratio: metric.ratio
    fillColor: metric.fill
  }

  NLinearGauge {
    visible: metric.ratio2 >= 0
    orientation: metric.vertical ? Qt.Horizontal : Qt.Vertical
    Layout.preferredWidth: metric.vertical ? metric.iconSize : metric.gaugeThickness
    Layout.preferredHeight: metric.vertical ? metric.gaugeThickness : metric.iconSize
    Layout.alignment: Qt.AlignCenter
    ratio: Math.max(0, metric.ratio2)
    fillColor: metric.fill2
  }
}
