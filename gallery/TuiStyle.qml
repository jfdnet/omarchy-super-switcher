pragma Singleton
import QtQuick
import qs.Commons

QtObject {
    // Qt 6.12 compat: shell renamed Color→ShellColor (omarchy#14511). Probe at runtime, keep both eras working.
    readonly property var pal: { try { return ShellColor } catch (e) { return Color } }

    readonly property color bg: pal.background
    readonly property color panel: pal.background
    readonly property color fg: pal.foreground
    readonly property color dim: pal.muted
    readonly property color line: pal.muted
    readonly property color accent: pal.accent
    readonly property color selection: Qt.rgba(pal.accent.r, pal.accent.g, pal.accent.b, 0.22)
    readonly property color inactiveBorder: Qt.rgba(pal.foreground.r, pal.foreground.g, pal.foreground.b, 0.32)
    readonly property color controlActiveBorder: pal.accent
    readonly property color surfaceRaised: Qt.rgba(pal.foreground.r, pal.foreground.g, pal.foreground.b, 0.10)
    readonly property color surfaceHover: Qt.rgba(pal.foreground.r, pal.foreground.g, pal.foreground.b, 0.18)
    readonly property color surfaceSubtle: Qt.rgba(pal.foreground.r, pal.foreground.g, pal.foreground.b, 0.06)
    readonly property color menuBorder: inactiveBorder
    readonly property color surfacePressed: surfaceHover
    readonly property color shellBorder: inactiveBorder
    readonly property color lineColor: line
    readonly property real dividerOpacity: 0.28
    function accentWash(color) { return Qt.rgba(color.r, color.g, color.b, 0.14) }
}
