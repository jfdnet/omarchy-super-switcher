pragma Singleton
import QtQuick
import qs.Commons

QtObject {
    // Qt 6.12 compat: shell renamed Color→ShellColor (omarchy#14511). Probe at runtime, keep both eras working.
    readonly property var pal: { try { return ShellColor } catch (e) { return Color } }

    readonly property color accent: pal.accent
    readonly property color accentSoft: Qt.rgba(pal.accent.r, pal.accent.g, pal.accent.b, 0.18)
    readonly property color accentBorder: pal.accent
    readonly property color accentActiveBorder: pal.accent
    readonly property color tintedBackground: pal.background
}
