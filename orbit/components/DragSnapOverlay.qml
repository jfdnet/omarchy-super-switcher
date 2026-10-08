import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "../SwitcherLogic.js" as Logic

PanelWindow {
    // Qt 6.12 compat: shell renamed Color→ShellColor (omarchy#14511). Probe at runtime, keep both eras working.
    readonly property var pal: { try { return ShellColor } catch (e) { return Color } }

  id: root

  required property var gesture
  required property var presentation
  required property var layouts
  property int selectedLayout: -1
  property int selectedSlot: -1
  readonly property var cardGeometry: Logic.dragPickerGeometry(gesture.monitor, presentation.anchor, Style.space(640), Style.space(318))

  function hitTest(globalX, globalY) {
    const local = picker.mapFromItem(root.contentItem, globalX - gesture.monitor.x, globalY - gesture.monitor.y)
    return picker.hitTest(local.x, local.y)
  }

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omarchy-orbit-drag-picker"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  // No input surface: the compositor retains the move grab. Pointer position
  // and the exact dragged-window identity arrive over its event socket instead.
  mask: Region {}

  Rectangle {
    x: root.cardGeometry.x
    y: root.cardGeometry.y
    width: root.cardGeometry.width
    height: root.cardGeometry.height
    radius: Style.cornerRadius * 2
    color: pal.menu.background
    border.width: 1
    border.color: pal.accent

    Text {
      anchors {
        top: parent.top
        topMargin: Style.space(14)
        horizontalCenter: parent.horizontalCenter
      }
      text: "Orbit · Drop onto a zone"
      color: pal.menu.text
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }
    SnapLayoutPicker {
      id: picker
      anchors {
        top: parent.top
        topMargin: Style.space(46)
        horizontalCenter: parent.horizontalCenter
      }
      layouts: root.layouts
      interactive: false
      selectedLayout: root.selectedLayout
      selectedSlot: root.selectedSlot
    }
    Text {
      anchors {
        bottom: parent.bottom
        bottomMargin: Style.space(12)
        horizontalCenter: parent.horizontalCenter
      }
      text: "Maximized = Super + Alt + F · Fullscreen = Super + F · Esc cancels"
      color: pal.menu.text
      opacity: 0.65
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.caption
    }
  }
}
