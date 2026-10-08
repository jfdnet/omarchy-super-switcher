pragma Singleton
import QtQuick
import qs.Commons

QtObject {
    // Qt 6.12 compat: shell renamed Color→ShellColor (omarchy#14511). Probe at runtime, keep both eras working.
    readonly property var pal: { try { return ShellColor } catch (e) { return Color } }

    readonly property QtObject colors: QtObject {
        // Keep the overview surfaces on Omarchy's active theme palette.
        property color colLayer1: pal.background
        property color colLayer1Hover: Qt.rgba(pal.foreground.r, pal.foreground.g, pal.foreground.b, 0.08)
        property color colLayer2: Qt.rgba(pal.foreground.r, pal.foreground.g, pal.foreground.b, 0.04)
        property color colLayer2Hover: Qt.rgba(pal.foreground.r, pal.foreground.g, pal.foreground.b, 0.08)
        property color colLayer2Active: Qt.rgba(pal.accent.r, pal.accent.g, pal.accent.b, 0.22)
        property color colOnLayer1: pal.foreground
        property color colSurfaceContainerLow: Qt.rgba(pal.foreground.r, pal.foreground.g, pal.foreground.b, 0.04)
        property color colSurfaceContainer: Qt.rgba(pal.foreground.r, pal.foreground.g, pal.foreground.b, 0.08)
    }
    readonly property QtObject font: QtObject {
        readonly property QtObject pixelSize: QtObject {
            property int smaller: 13
            property int small: 14
            property int normal: 16
        }
    }
    readonly property QtObject rounding: QtObject {
        property int small: 0
        property int large: 0
        property int verysmall: 0
    }
}
