pragma ComponentBehavior: Bound
import "."
import qs.Commons
import qs.Ui
import QtQuick
import Quickshell
import Quickshell.Wayland
import "ColorUtils.js" as ColorUtils

Item { // Window
    id: root
    property var toplevel
    property var windowData
    property bool captureActive: true
    property var monitorData
    property var scale
    property real scaleX: scale * widthRatio
    property real scaleY: scale * heightRatio
    property real widthRatio: {
        if (!widgetMonitor || !monitorData) return 1;
        const widgetWidth = widgetMonitor.transform & 1 ? widgetMonitor.height : widgetMonitor.width;
        const monitorWidth = monitorData.transform & 1 ? monitorData.height : monitorData.width;
        return (widgetWidth * monitorData.scale) / (monitorWidth * widgetMonitor.scale);
    }
    property real heightRatio: {
        if (!widgetMonitor || !monitorData) return 1;
        const widgetHeight = widgetMonitor.transform & 1 ? widgetMonitor.width : widgetMonitor.height;
        const monitorHeight = monitorData.transform & 1 ? monitorData.width : monitorData.height;
        return (widgetHeight * monitorData.scale) / (monitorHeight * widgetMonitor.scale);
    }
    property real initX: {
        return xOffset + localX;
    }

    property real initY: {
        return yOffset + localY;
    }
    property real xOffset: 0
    property real yOffset: 0
    property real workspaceWidth: 1
    property real workspaceHeight: 1
    property var widgetMonitor
    property int widgetMonitorId: widgetMonitor?.id ?? -1

    // Monitor logical dimensions (accounting for transforms)
    property real monitorLogicalWidth: {
        if (!monitorData) return 1920;
        const w = monitorData.transform & 1 ? monitorData.height : monitorData.width;
        const scale = Math.max(0.01, monitorData.scale ?? 1);
        return Math.max(1, w / scale
            - (monitorData.reserved?.[0] ?? 0)
            - (monitorData.reserved?.[2] ?? 0));
    }
    property real monitorLogicalHeight: {
        if (!monitorData) return 1080;
        const h = monitorData.transform & 1 ? monitorData.width : monitorData.height;
        const scale = Math.max(0.01, monitorData.scale ?? 1);
        return Math.max(1, h / scale
            - (monitorData.reserved?.[1] ?? 0)
            - (monitorData.reserved?.[3] ?? 0));
    }

    // Raw coordinate relative to the monitor the window claims to be on.
    // These may be stale after a cross-monitor move — Hyprland does not
    // re-tile windows on inactive workspaces.
    // During an output reconfigure Hyprland can publish a partial monitor or
    // client object for one event-loop turn. Keep every nested array access
    // safe while those snapshots are being replaced.
    property real rawRelX: (windowData?.at?.[0] ?? 0) - (monitorData?.x ?? 0) - (monitorData?.reserved?.[0] ?? 0)
    property real rawRelY: (windowData?.at?.[1] ?? 0) - (monitorData?.y ?? 0) - (monitorData?.reserved?.[1] ?? 0)
    property real rawW: windowData?.size?.[0] ?? 800
    property real rawH: windowData?.size?.[1] ?? 600

    // After scaling and clamping, would this window be too small to see?
    // This happens when stale coordinates place the window near/past the
    // monitor edge, so clamping squishes it to just a few pixels.
    property bool isRenderDegenerate: {
        const clampedX = Math.max(0, Math.min(rawRelX * root.scaleX, Math.max(0, workspaceWidth - 1)));
        const visibleW = Math.min(rawW * root.scaleX, Math.max(1, workspaceWidth - clampedX));
        const clampedY = Math.max(0, Math.min(rawRelY * root.scaleY, Math.max(0, workspaceHeight - 1)));
        const visibleH = Math.min(rawH * root.scaleY, Math.max(1, workspaceHeight - clampedY));
        // If either dimension is less than 10 % of the workspace box, the
        // window is effectively invisible — treat it as degenerate.
        return visibleW < workspaceWidth * 0.10 || visibleH < workspaceHeight * 0.10;
    }

    // When degenerate, center the window inside its workspace box at a
    // reasonable size; otherwise use the real Hyprland coordinates.
    property real effectiveW: isRenderDegenerate ? Math.min(rawW, monitorLogicalWidth) : rawW
    property real effectiveH: isRenderDegenerate ? Math.min(rawH, monitorLogicalHeight) : rawH
    property real effectiveRelX: isRenderDegenerate ? (monitorLogicalWidth - effectiveW) / 2 : rawRelX
    property real effectiveRelY: isRenderDegenerate ? (monitorLogicalHeight - effectiveH) / 2 : rawRelY

    property real rawLocalX: effectiveRelX * root.scaleX
    property real rawLocalY: effectiveRelY * root.scaleY
    property real rawWindowWidth: Math.max(1, effectiveW * root.scaleX)
    property real rawWindowHeight: Math.max(1, effectiveH * root.scaleY)
    property real localX: Math.max(0, Math.min(rawLocalX, Math.max(0, workspaceWidth - 1)))
    property real localY: Math.max(0, Math.min(rawLocalY, Math.max(0, workspaceHeight - 1)))
    property var targetWindowWidth: Math.max(1, Math.min(rawWindowWidth, Math.max(1, workspaceWidth - localX)))
    property var targetWindowHeight: Math.max(1, Math.min(rawWindowHeight, Math.max(1, workspaceHeight - localY)))
    property bool hovered: false
    property bool pressed: false
    property bool holdPosition: false
    property real holdX: 0
    property real holdY: 0
    property bool layoutOverrideEnabled: false
    property bool geometryAnimationEnabled: false
    property real layoutX: localX
    property real layoutY: localY
    property real layoutWidth: targetWindowWidth
    property real layoutHeight: targetWindowHeight
    property real layoutZ: 0

    x: holdPosition ? holdX : xOffset + (layoutOverrideEnabled ? layoutX : localX)
    y: holdPosition ? holdY : yOffset + (layoutOverrideEnabled ? layoutY : localY)
    width: layoutOverrideEnabled ? layoutWidth : targetWindowWidth
    height: layoutOverrideEnabled ? layoutHeight : targetWindowHeight
    // ScreencopyView delivers the first frame asynchronously. Fade a window
    // in when that frame arrives instead of making every workspace card flash
    // independently during Overview startup.
    opacity: root.anyPreviewContent || root.showingFreeze || root.captureAttempt >= 8 ? 1 : 0

    // Content arriving (capture landing, freeze showing) fades in instead of
    // popping, so rebuilds and expose-layout reshuffles read as transitions.
    Behavior on opacity {
        enabled: !root.Drag.active
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }

    Behavior on x {
        enabled: root.geometryAnimationEnabled && !root.Drag.active && !root.holdPosition
        NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
    }

    Behavior on y {
        enabled: root.geometryAnimationEnabled && !root.Drag.active && !root.holdPosition
        NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
    }

    Behavior on width {
        enabled: root.geometryAnimationEnabled && !root.Drag.active
        NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
    }

    Behavior on height {
        enabled: root.geometryAnimationEnabled && !root.Drag.active
        NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
    }

    function holdCurrentPosition() {
        holdX = x;
        holdY = y;
        holdPosition = true;
    }

    function restorePositionBinding() {
        x = Qt.binding(() => root.holdPosition ? root.holdX
            : root.xOffset + (root.layoutOverrideEnabled ? root.layoutX : root.localX));
        y = Qt.binding(() => root.holdPosition ? root.holdY
            : root.yOffset + (root.layoutOverrideEnabled ? root.layoutY : root.localY));
    }

    function releaseHeldPosition() {
        holdPosition = false;
    }

    property real topLeftRadius: 0
    property real topRightRadius: 0
    property real bottomLeftRadius: 0
    property real bottomRightRadius: 0
    clip: true

    property bool everHadContent: false
    property int captureAttempt: 0
    property int lastWorkspaceId: -1
    property int frontSlot: 0
    property bool slot0Armed: false
    property bool slot1Armed: false
    property url freezeUrl: ""
    property var captureToplevel: null
    // 全静态架构: 打开时一次单帧捕获 → 高清快照入 GlobalStates 仓库 →
    // disarm 双槽断流。此后卡片由 staticThumbnail Image 显示仓库静帧,
    // 拖动/换瓦片只是地址→静帧映射的搬运, 零捕获生命周期变化。
    property var thumbnailStore: null      // GalleryWindow 注入 GlobalStates.storeThumbnail
    property string thumbnailCacheKey: ""  // GalleryWindow 注入窗口地址
    property var lastKnownSourceSize: null
    readonly property url staticThumbnailUrl: {
        const _ = GlobalStates.thumbnailCacheRev;
        const grab = GlobalStates.thumbnailCache[root.thumbnailCacheKey];
        return grab?.url ?? "";
    }
    readonly property bool hasStaticThumbnail: root.staticThumbnailUrl != ""
    readonly property bool anyPreviewContent:
        preview0.hasContent || preview1.hasContent || root.hasStaticThumbnail
    readonly property bool showingFreeze: !root.anyPreviewContent && root.freezeUrl != ""

    function rememberToplevel() {
        if (root.toplevel)
            root.captureToplevel = root.toplevel;
    }

    function armFront() {
        // 已有静帧(本会话已捕获过或拖动搬运来的) → 不建流。
        // Hyprland 0.57 会话中途新建捕获上下文必败(quickshell#1418)。
        if (root.hasStaticThumbnail)
            return;
        root.rememberToplevel();
        if (!root.captureActive || !root.captureToplevel)
            return;
        if (root.frontSlot === 0)
            root.slot0Armed = true;
        else
            root.slot1Armed = true;
    }

    function recaptureNow() {
        if (!root.captureActive || root.hasStaticThumbnail)
            return;
        root.rememberToplevel();
        if (root.frontSlot === 0)
            root.slot1Armed = true;
        else
            root.slot0Armed = true;
    }

    function promoteSlot(slot) {
        root.frontSlot = slot;
        root.captureAttempt = 0;
        root.everHadContent = true;
        if (slot === 0)
            root.slot1Armed = false;
        else
            root.slot0Armed = false;
        root.snapshotPreview();
        // 首帧立即烘焙一版保底(打开后立刻拖动的场景: 拖动烘焙是异步的,
        // 源卡可能在回调前被销毁 → 仓库空窗 → 目标卡丢失截图)。首版可能
        // 带动画过渡态的纵横比, 400ms 落定烘焙会覆盖修正。
        root.storeSharpThumbnail();
        settleBakeTimer.restart();
    }

    // 拖动时兜底烘焙: 仅在实时流仍在时才有意义。落定断流后 previewHost
    // 双槽已空, 无条件烘焙会把空图写进仓库, 覆盖落定好图 → 拖移丢截图。
    function bakeIfLive() {
        if (preview0.hasContent || preview1.hasContent)
            root.storeSharpThumbnail();
    }

    // 高清静帧: 按窗口真实像素(上限 2560)采样入仓, 然后断流 —— 会话内
    // 该窗口不再有任何捕获活动。尺寸缺失(delegate 初建绑定未就绪)时用
    // 最后有效尺寸兜底, 连兜底都没有则 250ms 重试一次。
    function storeSharpThumbnail() {
        if (!root.anyPreviewContent)
            return;
        const size = root.windowData?.size;
        if (Array.isArray(size) && size[0] > 0 && size[1] > 0)
            root.lastKnownSourceSize = [size[0], size[1]];
        const effective = Array.isArray(size) && size[0] > 0 && size[1] > 0
            ? size : root.lastKnownSourceSize;
        if (!effective) {
            sharpStoreRetry.restart();
            return;
        }
        const grabTarget = Qt.size(Math.min(effective[0], 2560), Math.min(effective[1], 2560));
        previewHost.grabToImage(result => {
            if (!result?.url)
                return;
            if (root.thumbnailStore && root.thumbnailCacheKey)
                root.thumbnailStore(root.thumbnailCacheKey, result);
        }, grabTarget);
    }

    Timer {
        id: settleBakeTimer
        // 布局落定后重烘焙并断流: expose/打开动画约 300ms, 400ms 起卡片
        // 纵横比即最终值。重烘焙覆盖首帧保底版的瞬态形变。
        // 关键: disarm 必须在烘焙回调内执行 —— grabToImage 是异步渲染,
        // 若同步 disarm, 回调渲染时双槽已清空, 抓到空图覆盖好图,
        // 表现为全部卡片只剩壁纸(空图)透出来。
        interval: 400
        repeat: false
        onTriggered: {
            if (!root.captureActive)
                return;
            if (!(preview0.hasContent || preview1.hasContent))
                return;
            const size = root.windowData?.size;
            if (Array.isArray(size) && size[0] > 0 && size[1] > 0)
                root.lastKnownSourceSize = [size[0], size[1]];
            const effective = Array.isArray(size) && size[0] > 0 && size[1] > 0
                ? size : root.lastKnownSourceSize;
            if (!effective)
                return;
            const grabTarget = Qt.size(Math.min(effective[0], 2560), Math.min(effective[1], 2560));
            previewHost.grabToImage(result => {
                if (result?.url && root.thumbnailStore && root.thumbnailCacheKey)
                    root.thumbnailStore(root.thumbnailCacheKey, result);
                // 渲染已完成, 现在断流是安全的
                root.slot0Armed = false;
                root.slot1Armed = false;
            }, grabTarget);
        }
    }

    Timer {
        id: sharpStoreRetry
        interval: 250
        repeat: false
        onTriggered: {
            if (!root.hasStaticThumbnail)
                root.storeSharpThumbnail();
        }
    }

    // Return the grab result itself so the caller can keep the in-memory image
    // alive while a window is dragged across monitor surfaces. This is separate
    // from freezeUrl, which belongs to the capture replacement lifecycle.
    function grabPreview(callback) {
        if (!root.anyPreviewContent)
            return false;
        return previewHost.grabToImage(callback);
    }

    function snapshotPreview() {
        // Keep the original grab-to-image behavior. Quickshell may return a
        // non-file image URL, which Image can use while ScreencopyView is
        // being replaced during a drag.
        // During panel/plugin teardown the item can still report content for
        // one event-loop turn after it has lost its window. QQuickItem refuses
        // grabToImage in that state; more importantly, calling into the old
        // scene graph during hot reload can keep the shared shell busy.
        if (!root.anyPreviewContent || !previewHost.window)
            return;
        previewHost.grabToImage(result => {
            if (result?.url)
                root.freezeUrl = result.url;
        });
    }

    onToplevelChanged: root.rememberToplevel()

    onWindowDataChanged: {
        const ws = windowData?.workspace?.id ?? -1;
        if (root.holdPosition && ws > 0 && ws !== root.lastWorkspaceId)
            root.releaseHeldPosition();
        if (root.lastWorkspaceId > 0 && ws > 0 && ws !== root.lastWorkspaceId) {
            root.snapshotPreview();
            if (!root.anyPreviewContent)
                root.recaptureNow();
        }
        root.lastWorkspaceId = ws;
    }

    onCaptureActiveChanged: {
        if (root.captureActive) {
            root.armFront();
        } else {
            root.slot0Armed = false;
            root.slot1Armed = false;
            root.captureAttempt = 0;
            root.freezeUrl = "";
            root.everHadContent = false;
        }
    }

    // Keep a recent file-backed frame available while the live capture is
    // replaced. A move can stop both ScreencopyView slots for a short period.
    Timer {
        id: freezeTimer
        // 静帧架构: 断流后无实时内容, timer 自动停(running 条件只看双槽
        // hasContent)。仅在捕获建立初期(首帧已到、快照未落)短暂活跃。
        interval: 400
        repeat: true
        running: root.captureActive
            && (preview0.hasContent || preview1.hasContent)
        onTriggered: root.snapshotPreview()
    }

    Timer {
        id: captureWatchdog
        // 仅服务"会话中途新出现的窗口"(尚无静帧): 尝试建立一次捕获。
        // 已有静帧的窗口永不触发(断流后 hasContent=false 但 hasStatic=true,
        // 条件排除), 拖动后新卡也直接读仓库, 不走这里。
        interval: 50
        repeat: true
        running: root.captureActive && !root.anyPreviewContent && root.captureAttempt < 8
        onTriggered: {
            if (root.anyPreviewContent || !root.captureActive)
                return;
            root.captureAttempt += 1;
            root.recaptureNow();
        }
    }

    Component.onCompleted: {
        root.rememberToplevel();
        root.lastWorkspaceId = windowData?.workspace?.id ?? -1;
        if (root.captureActive)
            root.armFront();
    }

    Item {
        id: previewHost
        anchors.fill: parent

        ScreencopyView {
            id: preview0
            anchors.fill: parent
            captureSource: root.slot0Armed && root.captureActive && root.captureToplevel
                ? root.captureToplevel : null
            live: root.slot0Armed && root.captureActive
            visible: hasContent && (root.frontSlot === 0 || !preview1.hasContent)

            onHasContentChanged: {
                if (hasContent)
                    root.promoteSlot(0);
            }
            onStopped: {
                if (root.frontSlot === 0)
                    root.recaptureNow();
            }
        }

        ScreencopyView {
            id: preview1
            anchors.fill: parent
            captureSource: root.slot1Armed && root.captureActive && root.captureToplevel
                ? root.captureToplevel : null
            live: root.slot1Armed && root.captureActive
            visible: hasContent && (root.frontSlot === 1 || !preview0.hasContent)

            onHasContentChanged: {
                if (hasContent)
                    root.promoteSlot(1);
            }
            onStopped: {
                if (root.frontSlot === 1)
                    root.recaptureNow();
            }
        }
    }

    // 静帧层: 仓库里的高清快照, 会话期间的唯一窗口画面。实时流在快照
    // 入仓时已断开, 拖动换瓦片后新卡由此读取同一画面 —— 无重捕获。
    Image {
        id: staticThumbnail
        anchors.fill: parent
        visible: !preview0.hasContent && !preview1.hasContent
        source: root.staticThumbnailUrl
        // 保比例: 卡片纵横比与窗口一致的常态下与 Stretch 无异; 暴露
        // settle 竞态或单窗内边距等瞬态失配时宁可留边不可变形。
        fillMode: Image.PreserveAspectFit
        asynchronous: false
        cache: false
        smooth: true
    }

    Image {
        id: freezeImage
        anchors.fill: parent
        visible: root.showingFreeze
        source: root.freezeUrl
        fillMode: Image.Stretch
        asynchronous: false
        cache: false
        smooth: true
    }

    Rectangle {
            anchors.fill: parent
            topLeftRadius: root.topLeftRadius
            topRightRadius: root.topRightRadius
            bottomRightRadius: root.bottomRightRadius
            bottomLeftRadius: root.bottomLeftRadius
            color: pressed ? ColorUtils.transparentize(Appearance.colors.colLayer2Active, 0.5) :
                hovered ? ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 0.7) :
                ColorUtils.transparentize(Appearance.colors.colLayer2)
    }

    // Window previews do not draw their own outline. The workspace card border
    // is the single visual boundary for both the workspace and its previews.
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomRightRadius: root.bottomRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        border.width: 0
    }
}
