pragma ComponentBehavior: Bound
import "."
import QtQuick
import qs.Commons
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Wayland._ToplevelManagement

OverviewWindow {
    id: root

    required property string address
    required property var galleryRoot
    required property var screen
    required property int sourceWorkspaceId
    required property real previewX
    required property real previewY
    required property real previewWidth
    required property real previewHeight
    required property bool closeOnActivate
    property bool interactionEnabled: true

    signal activated(var windowData)

    property var liveWindowData: ServiceManager.workspace.clientByAddress(root.address)
    property var cachedWindowData: null
    property var modelToplevel: {
        const values = ToplevelManager.toplevels.values;
        for (let i = 0; i < values.length; ++i) {
            if (ServiceManager.workspace.normalizeAddress(values[i].HyprlandToplevel?.address) === root.address)
                return values[i];
        }
        return null;
    }
    property int monitorId: root.windowData?.monitor ?? -1
    property var sourceMonitor: ServiceManager.workspace.monitors.find(m => m.id === root.monitorId)
    property bool movedDuringPress: false
    property real pressSceneX: 0
    property real pressSceneY: 0
    property real pressLocalX: 0
    property real pressLocalY: 0
    readonly property string windowDropTargetKey: `${root.galleryRoot.monitor?.name ?? ""}:${root.closeOnActivate ? "large" : "small"}:${root.sourceWorkspaceId}:${root.address}`

    function placementForTarget(dropTarget) {
        if (!dropTarget || dropTarget.w <= 0 || dropTarget.h <= 0
                || dropTarget.workW <= 0 || dropTarget.workH <= 0)
            return null;
        const normalizedX = Math.max(0, Math.min(1,
            (CrossMonitorDrag.pointerX - dropTarget.x) / dropTarget.w));
        const normalizedY = Math.max(0, Math.min(1,
            (CrossMonitorDrag.pointerY - dropTarget.y) / dropTarget.h));
        return {
            dropX: dropTarget.workX + normalizedX * dropTarget.workW,
            dropY: dropTarget.workY + normalizedY * dropTarget.workH,
            restoreX: CrossMonitorDrag.pointerX,
            restoreY: CrossMonitorDrag.pointerY
        };
    }

    function publishWindowDropTarget() {
        if (!CrossMonitorDrag.active || root.width <= 0 || root.height <= 0)
            return;
        const point = root.mapToItem(null, 0, 0);
        CrossMonitorDrag.publishWindowTarget(
            root.windowDropTargetKey,
            root.address,
            root.sourceWorkspaceId,
            root.galleryRoot.monitorOriginX + point.x,
            root.galleryRoot.monitorOriginY + point.y,
            root.width,
            root.height);
    }

    function beginPointerDrag(pointerSceneX, pointerSceneY) {
        if (root.Drag.active)
            return;
        root.snapshotPreview();
        WorkspaceNavigation.beginWindowDrag(root.sourceWorkspaceId);
        CrossMonitorDrag.begin(
            root.address,
            root.sourceWorkspaceId,
            root.galleryRoot.monitor?.name ?? "",
            root.width,
            root.height,
            root.galleryRoot.monitorOriginX + pointerSceneX,
            root.galleryRoot.monitorOriginY + pointerSceneY,
            root.closeOnActivate);
        const generation = CrossMonitorDrag.generation;
        root.grabPreview(result => CrossMonitorDrag.setPreview(result, generation));
        root.movedDuringPress = true;
        root.Drag.active = true;
        root.Drag.source = root;
        root.Drag.hotSpot.x = root.pressLocalX;
        root.Drag.hotSpot.y = root.pressLocalY;
    }

    toplevel: root.modelToplevel
    captureActive: GlobalStates.overviewOpen
    monitorData: root.sourceMonitor
    widgetMonitor: root.galleryRoot.monitorData
    windowData: root.liveWindowData ?? root.cachedWindowData
    visible: !!root.windowData && root.windowData.mapped && !root.windowData.hidden
    xOffset: root.previewX
    yOffset: root.previewY
    workspaceWidth: root.previewWidth
    workspaceHeight: root.previewHeight
    scaleX: root.previewWidth / Math.max(1, root.galleryRoot.usableLogicalWidth(root.sourceMonitor))
    scaleY: root.previewHeight / Math.max(1, root.galleryRoot.usableLogicalHeight(root.sourceMonitor))
    scale: Math.min(scaleX, scaleY)
    opacity: root.Drag.active && root.closeOnActivate
        ? 0
        : (root.anyPreviewContent || root.showingFreeze || root.captureAttempt >= 8 ? 1 : 0)
    topLeftRadius: 5
    topRightRadius: 5
    bottomLeftRadius: 5
    bottomRightRadius: 5
    z: Drag.active ? 10000 : (root.layoutOverrideEnabled
        ? 30 + root.layoutZ
        : 20 + (root.windowData?.floating ? 2 : 0))

    onLiveWindowDataChanged: {
        if (root.liveWindowData)
            root.cachedWindowData = root.liveWindowData;
    }
    onXChanged: root.publishWindowDropTarget()
    onYChanged: root.publishWindowDropTarget()
    onWidthChanged: root.publishWindowDropTarget()
    onHeightChanged: root.publishWindowDropTarget()

    Connections {
        target: CrossMonitorDrag
        function onActiveChanged() {
            if (CrossMonitorDrag.active)
                root.publishWindowDropTarget();
        }
    }

    Component.onDestruction: CrossMonitorDrag.removeWindowTarget(root.windowDropTargetKey)

    // 捕获失败兜底(quickshell#1418: Hyprland 0.57 toplevel 截屏全挂):
    // captureAttempt 达到上限且无任何帧时, 用 app 图标+标题占位卡保住
    // "窗口存在/数量/位置"的可见性, 上游修复后自动回到实时缩略图。
    Rectangle {
        id: captureFallback
        visible: root.captureAttempt >= 8 && !root.anyPreviewContent && !root.showingFreeze
        anchors.fill: parent
        radius: 5
        color: Appearance.colors.colSurfaceContainer
        border.width: 1
        border.color: Appearance.colors.pillBorder
        opacity: 0.96

        Column {
            anchors.centerIn: parent
            spacing: 6
            width: parent.width * 0.9

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.windowData?.class
                    ? String(root.windowData.class).split(".").pop().slice(0, 1).toUpperCase()
                    : "?"
                color: Appearance.colors.colOnLayer1
                font.family: Style.font.family
                font.pixelSize: Math.max(18, Math.min(42, parent.width * 0.22))
                font.weight: Font.Bold
                renderType: Text.NativeRendering
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                maximumLineCount: 2
                wrapMode: Text.WordWrap
                text: root.windowData?.title ?? ""
                color: Appearance.colors.colOnLayer1
                opacity: 0.8
                font.family: Style.font.family
                font.pixelSize: 11
                renderType: Text.NativeRendering
            }
        }
    }

    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: height / 2

    MouseArea {
        id: dragArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        drag.target: parent
        drag.threshold: 8
        enabled: root.interactionEnabled

        onEntered: root.hovered = true
        onExited: root.hovered = false

        onPositionChanged: mouse => {
            if (!root.pressed)
                return;
            const point = dragArea.mapToItem(null, mouse.x, mouse.y);
            if (!root.Drag.active
                    && (Math.abs(point.x - root.pressSceneX) > dragArea.drag.threshold
                        || Math.abs(point.y - root.pressSceneY) > dragArea.drag.threshold))
                root.beginPointerDrag(point.x, point.y);
            if (!root.Drag.active)
                return;
            CrossMonitorDrag.updatePointer(
                root.galleryRoot.monitorOriginX + point.x,
                root.galleryRoot.monitorOriginY + point.y);
        }

        onPressed: mouse => {
            if (mouse.button !== Qt.LeftButton)
                return;
            const point = dragArea.mapToItem(null, mouse.x, mouse.y);
            root.movedDuringPress = false;
            root.pressSceneX = point.x;
            root.pressSceneY = point.y;
            root.pressLocalX = mouse.x;
            root.pressLocalY = mouse.y;
            root.pressed = true;
        }

        onReleased: {
            if (!root.pressed)
                return;
            if (!root.Drag.active) {
                root.pressed = false;
                return;
            }
            const dropTarget = CrossMonitorDrag.hoveredTarget;
            const targetWorkspace = dropTarget?.id
                ?? GlobalStates.overviewDraggingTargetWorkspace;
            const targetIsTrailing = dropTarget?.isTrailing
                ?? GlobalStates.overviewDraggingTargetIsTrailing;
            const targetMonitor = dropTarget?.workspaceMonitorName
                ?? GlobalStates.overviewDraggingTargetMonitor;
            const placement = root.placementForTarget(dropTarget);
            const layoutAlreadyCommitted = CrossMonitorDrag.liveReordered;
            CrossMonitorDrag.end();
            root.pressed = false;
            root.Drag.active = false;
            root.restorePositionBinding();
            WorkspaceNavigation.commitWindowDrag(
                root.address,
                root.sourceWorkspaceId,
                targetWorkspace,
                targetIsTrailing,
                targetMonitor,
                placement,
                layoutAlreadyCommitted);
        }

        onDoubleClicked: event => {
            if (event.button !== Qt.LeftButton || root.movedDuringPress)
                return;
            // Top-strip thumbnails: double-click enters the workspace — the
            // card's own TapHandler only receives taps on the card background.
            if (!root.closeOnActivate && root.galleryRoot) {
                root.galleryRoot.activationPending(
                    { workspace: String(root.sourceWorkspaceId) });
                root.galleryRoot.closeRequested(false);
                event.accepted = true;
            }
        }

        onClicked: event => {
            if (!root.windowData)
                return;
            if (root.movedDuringPress) {
                event.accepted = true;
                return;
            }
            if (event.button === Qt.MiddleButton) {
                Hyprland.dispatch(`hl.dsp.window.close({window = "address:${root.address}"})`);
                event.accepted = true;
                return;
            }
            if (event.button === Qt.LeftButton && !root.Drag.active) {
                root.activated(root.windowData);
                event.accepted = true;
            }
        }
    }
}
