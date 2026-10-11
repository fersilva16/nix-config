// GPU state for the bar widget and panel (CPU/RAM come from noctalia's
// SystemStatService): one long-lived nvidia-smi
// streaming a CSV line per sample (no fork per refresh).
import QtQuick
import Quickshell.Io

Item {
  id: root

  property var pluginApi: null

  readonly property int intervalMs: 2000
  readonly property int historyLength: 60

  property bool available: false
  property string name: ""
  property real usage: 0
  property real vramUsedMib: 0
  property real vramTotalMib: 0
  property real temp: 0
  property real power: 0
  property real powerLimit: 0
  readonly property real vramPercent: vramTotalMib > 0 ? vramUsedMib / vramTotalMib * 100 : 0

  property var usageHistory: []
  property var vramHistory: []
  property var tempHistory: []

  function pushed(history, value) {
    const h = history.concat([value]);
    return h.length > historyLength ? h.slice(h.length - historyLength) : h;
  }

  // "15, 1019, 16303, 41, 23.50, 300.00, NVIDIA GeForce RTX 5070 Ti"
  // Unsupported fields read "[N/A]" and parse to 0.
  function parse(line) {
    const f = line.split(",").map(s => s.trim());
    if (f.length < 7)
      return;
    usage = parseFloat(f[0]) || 0;
    vramUsedMib = parseFloat(f[1]) || 0;
    vramTotalMib = parseFloat(f[2]) || 0;
    temp = parseFloat(f[3]) || 0;
    power = parseFloat(f[4]) || 0;
    powerLimit = parseFloat(f[5]) || 0;
    name = f.slice(6).join(",");
    available = true;
    usageHistory = pushed(usageHistory, usage);
    vramHistory = pushed(vramHistory, vramPercent);
    tempHistory = pushed(tempHistory, temp);
  }

  Process {
    id: smi
    running: true
    command: ["@nvidiaSmi@", "-i", "0", "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,power.limit,name", "--format=csv,noheader,nounits", "-lms", String(root.intervalMs)]
    stdout: SplitParser {
      onRead: line => root.parse(line)
    }
    onExited: {
      root.available = false;
      restartTimer.start();
    }
  }

  // nvidia-smi only exits on driver trouble; back off instead of spinning.
  Timer {
    id: restartTimer
    interval: 10000
    onTriggered: smi.running = true
  }
}
