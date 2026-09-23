pragma ComponentBehavior: Bound
import "."
import qs.Commons
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Wayland._ToplevelManagement
import Quickshell.Hyprland
import "ColorUtils.js" as ColorUtils

Item {
    id: root

    signal closeRequested(bool commitSelection)
    signal activationPending(var payload)

    required property var screen
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property var monitorData: ServiceManager.workspace.monitors.find(m => m.id === root.monitor?.id)
    readonly property real monitorOriginX: root.monitorData?.x ?? 0
    readonly property real monitorOriginY: root.monitorData?.y ?? 0
    readonly property int modelRevision: ServiceManager.workspace.dataSerial
        + GlobalStates.overviewRefreshSerial
        + (ToplevelManager.toplevels.values?.length ?? 0)
    readonly property url wallpaperUrl: Wallpaper.readyUrl !== ""
        ? Wallpaper.readyUrl : Wallpaper.requestedUrl
    readonly property var entries: {
        // Re-evaluates on every model tick, but only swaps the array when the
        // VISUAL structure actually changed (ids, order, trailing slot) —
        // identical layouts keep the same reference, so the ListView, its
        // delegates and their thumbnail captures never rebuild just because a
        // serial bumped or pending flags flipped. While a drag/compaction
        // batch mutates pending state statement by statement, rendering stays
        // frozen on the current layout; the single post-batch recompute then
        // diffs pre-drop vs final directly.
        if (GlobalStates.stripTransitionsSuspended)
            return root.stableEntries;
        const revision = root.modelRevision;
        void revision;
        const name = root.monitor?.name ?? "";
        const scoped = ServiceManager.workspace.overviewWorkspaceEntriesForMonitor(
            name, true, {}, true, true) ?? [];
        const next = scoped.length > 0
            ? scoped
            : (ServiceManager.workspace.overviewWorkspaceEntries ?? []);
        const key = JSON.stringify(next.map(entry => ({
            id: entry.id,
            trailing: entry.isTrailingEmpty === true,
            monitor: entry.monitorName ?? ""
        })));
        if (key !== root.stableEntriesKey) {
            root.stableEntriesKey = key;
            root.stableEntries = next;
        }
        return root.stableEntries;
    }
    property var stableEntries: []
    property string stableEntriesKey: ""
    readonly property var entryIds: root.entries.map(entry => entry.id)
    readonly property int selectedWorkspaceId: GlobalStates.overviewFocusedWorkspaceId > 0
        ? GlobalStates.overviewFocusedWorkspaceId
        : Math.max(1, root.monitor?.activeWorkspace?.id ?? 1)
    readonly property var selectedEntry: root.entries.find(entry => entry.id === root.selectedWorkspaceId)
        ?? root.entries[0]
        ?? null
    readonly property int selectedIndex: Math.max(0,
        root.entries.findIndex(entry => entry.id === root.selectedWorkspaceId))
    readonly property bool ownsGesture: (root.monitor?.name ?? "")
        === GlobalStates.overviewAnchorMonitorName

    readonly property real topHeight: height * 0.20
    readonly property real bottomY: topHeight
    readonly property real bottomHeight: height * 0.80
    readonly property real cardGap: 14
    readonly property real topCardHeight: Math.max(92, topHeight - 34)
    readonly property real topCardWidth: topCardHeight * usableLogicalWidth(root.monitorData)
        / Math.max(1, usableLogicalHeight(root.monitorData))
    readonly property real bottomMargin: 22
    readonly property real bottomCardX: bottomMargin
    readonly property real bottomCardY: bottomY + 12
    readonly property real bottomCardWidth: width - bottomMargin * 2
    readonly property real bottomCardHeight: Math.max(1, height - bottomCardY - bottomMargin)
    readonly property real pageGap: 24
    readonly property real pageSpan: bottomCardWidth + pageGap
    property real swipeOffset: 0
    property bool swipeActive: false
    property bool swipeSettling: false
    property real swipeVelocity: 0
    property real lastSwipeTimestamp: 0
    property int swipeStartIndex: -1
    property int settlementIndex: -1
    property int clickedWorkspaceId: -1
    property int settleEasingType: Easing.OutCubic
    property var compactionHandoffGrab: null
    property url compactionHandoffUrl: ""
    readonly property bool workspaceInteractionEnabled: !root.swipeActive
        && !root.swipeSettling
        && !GlobalStates.overviewCompactionAnimating
        && !GlobalStates.overviewCompactionSyncing
    readonly property int swipePreviewIndex: {
        if (root.swipeSettling && root.settlementIndex >= 0)
            return root.settlementIndex;
        if (!root.swipeActive || root.swipeStartIndex < 0 || Math.abs(root.swipeOffset) < 4)
            return root.selectedIndex;
        const candidate = root.swipeStartIndex + (root.swipeOffset < 0 ? 1 : -1);
        return candidate >= 0 && candidate < root.entries.length
            ? candidate : root.swipeStartIndex;
    }
    readonly property int highlightedWorkspaceId: root.entries[root.swipePreviewIndex]?.id
        ?? root.selectedWorkspaceId

    function usableLogicalWidth(mon) {
        const transform = mon?.transform ?? 0;
        const physical = (transform & 1) ? (mon?.height ?? root.screen.width) : (mon?.width ?? root.screen.width);
        const scale = Math.max(0.01, mon?.scale ?? 1);
        return Math.max(1, physical / scale - (mon?.reserved?.[0] ?? 0) - (mon?.reserved?.[2] ?? 0));
    }

    function usableLogicalHeight(mon) {
        const transform = mon?.transform ?? 0;
        const physical = (transform & 1) ? (mon?.width ?? root.screen.height) : (mon?.height ?? root.screen.height);
        const scale = Math.max(0.01, mon?.scale ?? 1);
        return Math.max(1, physical / scale - (mon?.reserved?.[1] ?? 0) - (mon?.reserved?.[3] ?? 0));
    }

    function effectiveWorkspaceId(win, address) {
        const pending = GlobalStates.overviewPendingWindowWorkspaceByAddress ?? {};
        return Number(pending[address] ?? pending[ServiceManager.workspace.normalizeAddress(address)]
            ?? win?.workspace?.id ?? -1);
    }

    function windowAddressesForWorkspace(workspaceId) {
        const revision = root.modelRevision;
        const pending = GlobalStates.overviewPendingWindowWorkspaceByAddress;
        void revision; void pending;
        return ToplevelManager.toplevels.values.map(toplevel => {
            const address = ServiceManager.workspace.normalizeAddress(toplevel.HyprlandToplevel?.address);
            const win = ServiceManager.workspace.clientByAddress(address);
            if (!win?.mapped || win?.hidden)
                return "";
            return root.effectiveWorkspaceId(win, address) === workspaceId ? address : "";
        }).filter(address => address.length > 0);
    }

    function clamp01(value) {
        return Math.max(0, Math.min(1, Number(value)));
    }

    function jellyProgress(value) {
        const t = root.clamp01(value);
        // A restrained back-ease: it overshoots once, then settles without the
        // mechanical feel of a plain cubic slide.
        const overshoot = 1.35;
        const shifted = t - 1;
        return 1 + (overshoot + 1) * shifted * shifted * shifted
            + overshoot * shifted * shifted;
    }

    function compactionVisualForWorkspace(workspaceId) {
        const neutral = { x: 0, y: 0, opacity: 1, rotation: 0, xScale: 1, yScale: 1, active: false };
        if (!GlobalStates.overviewCompactionAnimating)
            return neutral;

        const id = Number(workspaceId);
        const elapsed = Number(GlobalStates.overviewCompactionElapsed ?? 0);
        const timeline = GlobalStates.overviewCompactionTimeline
            ?? { emptyStages: [], shiftStages: [] };
        let x = 0;
        let y = 0;
        let opacity = 1;
        let rotation = 0;
        let xScale = 1;
        let yScale = 1;
        let active = false;

        for (const shift of timeline.shiftStages ?? []) {
            if (id <= Number(shift.afterWorkspaceId) || elapsed < Number(shift.start))
                continue;
            const t = root.clamp01((elapsed - Number(shift.start)) / Number(shift.duration));
            x -= Number(shift.slots) * (root.topCardWidth + root.cardGap)
                * root.jellyProgress(t);
            const pulse = Math.sin(Math.PI * t) * 0.045;
            xScale += pulse;
            yScale -= pulse * 0.72;
            active = true;
        }

        const empty = (timeline.emptyStages ?? []).find(stage =>
            Number(stage.workspaceId) === id);
        if (empty && elapsed >= Number(empty.start)) {
            const t = root.clamp01((elapsed - Number(empty.start)) / Number(empty.duration));
            const travel = root.jellyProgress(t);
            x -= root.topCardWidth * 0.24 * travel;
            y -= (root.topCardHeight + 18) * travel;
            rotation = -7 * Math.sin(Math.PI * t);
            const pulse = Math.sin(Math.PI * t);
            xScale += 0.075 * pulse;
            yScale -= 0.055 * pulse;
            opacity = t < 0.72 ? 1 : 1 - root.clamp01((t - 0.72) / 0.28);
            active = true;
        }

        return { x, y, opacity, rotation, xScale, yScale, active };
    }

    function captureCompactionHandoff() {
        topList.grabToImage(result => {
            root.compactionHandoffGrab = result;
            root.compactionHandoffUrl = result.url;
        });
    }

    function selectWorkspace(workspaceId) {
        if (workspaceId < 1)
            return;
        GlobalStates.overviewFocusedWorkspaceId = workspaceId;
        const index = root.entries.findIndex(entry => entry.id === workspaceId);
        if (index >= 0)
            topList.positionViewAtIndex(index, ListView.Contain);
    }

    function animateToWorkspace(workspaceId) {
        const targetIndex = root.entries.findIndex(entry => entry.id === workspaceId);
        if (targetIndex < 0)
            return;
        if (targetIndex === root.selectedIndex) {
            root.selectWorkspace(workspaceId);
            return;
        }
        if (root.swipeActive
                || GlobalStates.overviewCompactionAnimating
                || GlobalStates.overviewCompactionSyncing)
            return;
        root.clickedWorkspaceId = workspaceId;
        if (root.swipeSettling)
            return;

        const distance = Math.abs(targetIndex - root.selectedIndex);
        root.swipeStartIndex = root.selectedIndex;
        root.settlementIndex = targetIndex;
        root.swipeOffset = 0;
        settleAnimation.to = (root.selectedIndex - targetIndex) * root.pageSpan;
        settleAnimation.duration = Math.min(800, 260 + (distance - 1) * 125);
        root.settleEasingType = Easing.InOutCubic;
        root.swipeSettling = true;
        topList.positionViewAtIndex(targetIndex, ListView.Contain);
        settleAnimation.start();
    }

    function navigate(delta) {
        if (root.entries.length === 0)
            return;
        let index = root.entries.findIndex(entry => entry.id === root.selectedWorkspaceId);
        if (index < 0)
            index = 0;
        index = (index + delta + root.entries.length) % root.entries.length;
        root.selectWorkspace(root.entries[index].id);
    }

    function beginSwipe(deltaX, timestamp) {
        if (!root.ownsGesture || root.swipeSettling || root.entries.length === 0)
            return;
        root.clickedWorkspaceId = -1;
        settleAnimation.stop();
        root.swipeActive = true;
        root.swipeStartIndex = root.selectedIndex;
        root.swipeOffset = 0;
        root.swipeVelocity = 0;
        root.lastSwipeTimestamp = timestamp;
        root.applySwipeDelta(deltaX, timestamp);
    }

    function applySwipeDelta(deltaX, timestamp) {
        if (!root.ownsGesture || !root.swipeActive || root.swipeSettling)
            return;
        const scaledDelta = Number(deltaX) * 3.2;
        const elapsed = Math.max(1, Number(timestamp) - root.lastSwipeTimestamp);
        const instantaneousVelocity = scaledDelta / elapsed;
        root.swipeVelocity = root.swipeVelocity * 0.72 + instantaneousVelocity * 0.28;
        root.lastSwipeTimestamp = Number(timestamp);

        let nextOffset = root.swipeOffset + scaledDelta;
        const movingToPrevious = nextOffset > 0;
        const targetIndex = root.swipeStartIndex + (movingToPrevious ? -1 : 1);
        if (targetIndex < 0 || targetIndex >= root.entries.length)
            nextOffset = nextOffset * 0.28;
        root.swipeOffset = Math.max(-root.pageSpan * 1.04,
            Math.min(root.pageSpan * 1.04, nextOffset));
        if (targetIndex >= 0 && targetIndex < root.entries.length)
            topList.positionViewAtIndex(targetIndex, ListView.Contain);
    }

    function endSwipe(cancelled) {
        if (!root.ownsGesture || !root.swipeActive)
            return;
        root.swipeActive = false;
        const direction = root.swipeOffset < 0 ? 1 : -1;
        const targetIndex = root.swipeStartIndex + direction;
        const targetExists = targetIndex >= 0 && targetIndex < root.entries.length;
        const passedDistance = Math.abs(root.swipeOffset) >= root.bottomCardWidth * 0.22;
        const passedVelocity = Math.abs(root.swipeVelocity) >= 0.58
            && Math.sign(root.swipeVelocity) === Math.sign(root.swipeOffset);
        const commit = !cancelled && targetExists && (passedDistance || passedVelocity);

        root.settlementIndex = commit ? targetIndex : root.swipeStartIndex;
        if (root.settlementIndex >= 0)
            topList.positionViewAtIndex(root.settlementIndex, ListView.Contain);
        settleAnimation.to = commit ? -direction * root.pageSpan : 0;
        settleAnimation.duration = commit ? 230 : 200;
        root.settleEasingType = Easing.OutCubic;
        root.swipeSettling = true;
        settleAnimation.start();
    }

    function startStep(delta) {
        if (root.swipeActive || root.swipeSettling || root.entries.length === 0)
            return;
        const targetIndex = root.selectedIndex + (delta > 0 ? 1 : -1);
        if (targetIndex < 0 || targetIndex >= root.entries.length)
            return;
        root.swipeStartIndex = root.selectedIndex;
        root.settlementIndex = targetIndex;
        root.swipeOffset = 0;
        settleAnimation.to = delta > 0 ? -root.pageSpan : root.pageSpan;
        settleAnimation.duration = 260;
        root.settleEasingType = Easing.OutCubic;
        root.swipeSettling = true;
        settleAnimation.start();
    }

    function requestStep(delta) {
        if (!root.ownsGesture)
            return;
        root.clickedWorkspaceId = -1;
        root.startStep(delta);
    }

    function finishSettlement() {
        if (root.settlementIndex >= 0 && root.settlementIndex < root.entries.length
                && root.settlementIndex !== root.selectedIndex)
            root.selectWorkspace(root.entries[root.settlementIndex].id);
        root.swipeOffset = 0;
        root.swipeVelocity = 0;
        root.swipeStartIndex = -1;
        root.settlementIndex = -1;
        root.swipeSettling = false;
        root.clickedWorkspaceId = -1;
    }

    function activateWindow(windowData) {
        if (!windowData?.address)
            return
        // Gallery 层持有独占键盘焦点期间，窗口 focus 派发不生效——
        // 先暂存目标，关闭动画结束（层释放焦点）后再派发。
        const cx = (windowData.at?.[0] ?? 0) + (windowData.size?.[0] ?? 0) / 2
        const cy = (windowData.at?.[1] ?? 0) + (windowData.size?.[1] ?? 0) / 2
        root.activationPending({ addr: windowData.address, cx: cx, cy: cy })
        root.closeRequested(false)
    }


    function registerDropTarget(item, entry) {
        const point = item.mapToItem(null, 0, 0);
        const targetMonitor = ServiceManager.workspace.monitors.find(
            monitor => monitor.name === (entry?.monitorName ?? "")) ?? root.monitorData;
        const reserved = targetMonitor?.reserved ?? [0, 0, 0, 0];
        CrossMonitorDrag.publishTarget(
            root.monitor?.name ?? "",
            entry?.monitorName ?? "",
            entry?.id ?? -1,
            entry?.isTrailingEmpty ?? false,
            root.monitorOriginX + point.x,
            root.monitorOriginY + point.y,
            item.width,
            item.height,
            (targetMonitor?.x ?? root.monitorOriginX) + (reserved[0] ?? 0),
            (targetMonitor?.y ?? root.monitorOriginY) + (reserved[1] ?? 0),
            root.usableLogicalWidth(targetMonitor),
            root.usableLogicalHeight(targetMonitor));
    }

    onEntriesChanged: {
        root.updateTopStripTransitions();
        if (!root.entries.some(entry => entry.id === root.selectedWorkspaceId)) {
            const fallback = root.entries.find(entry => !entry.isTrailingEmpty) ?? root.entries[0];
            if (fallback)
                root.selectWorkspace(fallback.id);
        }
    }

    // ---- Top-strip transitions ------------------------------------------------
    // The strip model is a plain array, so reassignments rebuild every delegate
    // without ListView transitions. Diff entries on each change and hand each
    // rebuilt delegate a start-offset plan:
    //  - emptied workspaces leave as upward-sliding ghosts;
    //  - the trailing empty slot is a persistent entity — it slides left into
    //    the vacated position when the strip shrinks, and only enters from the
    //    screen's right edge when the strip grows (a drop just filled it);
    //  - occupied cards slide from their old slot; a freshly filled slot
    //    keeps its position; brand-new workspaces enter from the right edge.
    property var previousTopEntries: null
    property var introPlans: ({})
    property var exitingTopCards: []
    // Tune the strip pacing here: reveal beat, slide/displacement and exit
    // durations.
    readonly property int topStripIntroPause: 450
    readonly property int topStripIntroDuration: 1100
    readonly property int topStripGhostDuration: 900

    Timer {
        id: topGhostCleanupTimer
        interval: root.topStripGhostDuration + 60
        repeat: false
        onTriggered: root.exitingTopCards = []
    }

    Timer {
        id: topIntroCleanupTimer
        interval: root.topStripIntroPause + root.topStripIntroDuration + 80
        repeat: false
        onTriggered: root.introPlans = ({})
    }

    // Overlay reveal for structure-preserving drops (see onStripRevealTick).
    property var enteringTopCard: null

    Timer {
        id: topEnteringCleanupTimer
        interval: root.topStripIntroPause + root.topStripIntroDuration + 140
        repeat: false
        onTriggered: root.enteringTopCard = null
    }

    function topCardXForIndex(index) {
        return topList.x + index * (root.topCardWidth + root.cardGap) - topList.contentX;
    }

    function topStripEdgeEntryPlan(index) {
        // Start half-visible at the screen's right edge: the reveal pauses
        // there briefly before the card glides in.
        return {
            offset: Math.max(root.topCardWidth * 0.5 + root.cardGap,
                root.width - root.topCardWidth * 0.5 - root.topCardXForIndex(index)),
            fade: true,
            startAt: Date.now()
        };
    }

    function updateTopStripTransitions() {
        // A batch is mutating pending state — keep the pre-batch layout as the
        // diff baseline and issue nothing until it completes.
        if (GlobalStates.stripTransitionsSuspended)
            return;
        // Compaction (animated choreography or silent renumber) re-keys ids in
        // place; re-arm silently while it runs so the diff never stacks motion
        // on top of it. In-flight slot-keyed plans survive the re-keys.
        if (WorkspaceNavigation.compactingWorkspaces
                || GlobalStates.overviewCompactionAnimating
                || GlobalStates.overviewCompactionSyncing) {
            root.previousTopEntries = null;
            return;
        }
        const previous = root.previousTopEntries;
        if (previous === null) {
            root.previousTopEntries = root.entries;
            return;
        }

        const previousOccupied = ({});
        let previousTrailingIndex = -1;
        let previousTrailingId = -1;
        previous.forEach((entry, index) => {
            if (entry.isTrailingEmpty) {
                previousTrailingIndex = index;
                previousTrailingId = entry.id;
            } else {
                previousOccupied[entry.id] = index;
            }
        });
        const nextOccupied = ({});
        root.entries.forEach((entry, index) => {
            if (!entry.isTrailingEmpty)
                nextOccupied[entry.id] = index;
        });

        // Transition rules (plans keyed by ARRIVAL SLOT — "t" for the empty
        // slot's stable letter identity, "s<index>" for occupied cards — so
        // the real-time renumbering that re-keys ids in place never orphans a
        // running animation):
        //  - the empty slot is BORN when the old number got filled (even if
        //    the source emptied in the same action) or the strip grew:
        //    reveal from the right edge with its beat; otherwise it continues
        //    and only glides when the strip shrinks under it;
        //  - occupied cards glide from their old slot; a card filling the
        //    empty slot's position, or continuing in the slot of the emptied
        //    workspace, keeps its position;
        //  - removed cards whose slot no stationary card inherits ghost up.
        const fillHappened = previousTrailingId > 0
            && nextOccupied[previousTrailingId] !== undefined;
        const grew = root.entries.length > previous.length;

        const plans = ({});
        const now = Date.now();
        root.entries.forEach((entry, index) => {
            const newX = root.topCardXForIndex(index);
            if (entry.isTrailingEmpty) {
                if (fillHappened || grew || previousTrailingIndex < 0) {
                    plans["t"] = root.topStripEdgeEntryPlan(index);
                } else {
                    const offset = root.topCardXForIndex(previousTrailingIndex) - newX;
                    if (offset !== 0)
                        plans["t"] = { offset, fade: false, startAt: now };
                }
                return;
            }
            if (previousOccupied[entry.id] !== undefined) {
                const offset = root.topCardXForIndex(previousOccupied[entry.id]) - newX;
                if (offset !== 0)
                    plans[`s${index}`] = { offset, fade: false, startAt: now };
                return;
            }
            const previousAtSlot = previous[index];
            if (previousAtSlot && previousAtSlot.isTrailingEmpty)
                return;   // this card just filled the empty slot — keep its place
            if (previousAtSlot && nextOccupied[previousAtSlot.id] === undefined
                    && previousAtSlot.id !== entry.id)
                return;   // slot continuity — the emptied workspace's card lives on here
            plans[`s${index}`] = root.topStripEdgeEntryPlan(index);
        });

        const ghosts = [];
        for (const idKey of Object.keys(previousOccupied)) {
            if (nextOccupied[idKey] !== undefined)
                continue;
            const oldIndex = previousOccupied[idKey];
            const replacement = root.entries[oldIndex];
            if (replacement && !replacement.isTrailingEmpty
                    && plans[`s${oldIndex}`] === undefined)
                continue;   // a stationary card continues in this slot (re-key)
            ghosts.push({
                id: Number(idKey),
                x: root.topCardXForIndex(oldIndex)
            });
        }
        if (ghosts.length > 0) {
            root.exitingTopCards = root.exitingTopCards.concat(ghosts);
            topGhostCleanupTimer.restart();
        }
        if (Object.keys(plans).length > 0) {
            root.introPlans = plans;
            topIntroCleanupTimer.restart();
        }
        root.previousTopEntries = root.entries;
    }

    Connections {
        target: GlobalStates
        function onOverviewCompactionHandoffChanged() {
            if (GlobalStates.overviewCompactionHandoff) {
                clearCompactionHandoffTimer.stop();
                root.captureCompactionHandoff();
            } else if (root.compactionHandoffUrl.toString().length > 0) {
                clearCompactionHandoffTimer.restart();
            }
        }
        function onGallerySwipeStarted(deltaX, timestamp) {
            root.beginSwipe(deltaX, timestamp);
        }
        function onStripRevealTickChanged() {
            if (GlobalStates.stripRevealTick <= 0)
                return;
            const index = root.entries.length - 1;
            if (index < 0 || !root.entries[index].isTrailingEmpty)
                return;
            // The strip structure is unchanged — tell the story with
            // overlays: the source card retires with a ghost exit while a
            // temporary card reveals from the right edge onto the empty slot.
            const fromSlot = GlobalStates.stripRevealSourceSlot;
            if (fromSlot >= 0 && fromSlot < index) {
                root.exitingTopCards = root.exitingTopCards.concat([{
                    id: -1,
                    x: root.topCardXForIndex(fromSlot)
                }]);
                topGhostCleanupTimer.restart();
            }
            root.enteringTopCard = ({ index: index, startAt: Date.now() });
            topEnteringCleanupTimer.restart();
        }
        function onGallerySwipeUpdated(deltaX, timestamp) {
            root.applySwipeDelta(deltaX, timestamp);
        }
        function onGallerySwipeFinished(cancelled, timestamp) {
            void timestamp;
            root.endSwipe(cancelled);
        }
        function onGalleryStepRequested(delta) {
            root.requestStep(delta);
        }
    }

    NumberAnimation {
        id: settleAnimation
        target: root
        property: "swipeOffset"
        easing.type: root.settleEasingType
        onFinished: root.finishSettlement()
    }

    Timer {
        id: clearCompactionHandoffTimer
        interval: 180
        repeat: false
        onTriggered: {
            root.compactionHandoffUrl = "";
            root.compactionHandoffGrab = null;
        }
    }

    // Opaque, wallpaper-backed backdrop (Mission Control style): the live
    // desktop never shows through the overlay, so window movements behind it
    // — drops onto the visible workspace, renumbering, focus dances — can
    // never read as screen flashes. The bottom preview already paints the
    // same wallpaper, so the backdrop reads as one surface.
    Image {
        anchors.fill: parent
        source: root.wallpaperUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        cache: true
    }

    Rectangle {
        anchors.fill: parent
        color: ColorUtils.transparentize(TuiStyle.bg, 0.3)
    }

    Rectangle {
        x: 0
        y: 0
        width: parent.width
        height: root.topHeight
        color: ColorUtils.transparentize(Appearance.colors.colSurfaceContainer, 0.08)
        border.width: 0
    }

    ListView {
        id: topList
        x: root.cardGap
        y: 12
        width: root.width - root.cardGap * 2
        height: root.topCardHeight
        orientation: ListView.Horizontal
        spacing: root.cardGap
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.entries

        delegate: Rectangle {
            id: topCard
            required property var modelData
            required property int index
            width: root.topCardWidth
            height: root.topCardHeight
            radius: 10
            clip: true
            color: Appearance.colors.colSurfaceContainerLow
            border.width: 0
            readonly property var compactionVisual:
                root.compactionVisualForWorkspace(topCard.modelData.id)
            // Edge-entry choreography: the card first shows up half-visible
            // at the screen's right edge, holds there for a beat, then glides
            // in over its neighbours. Plans carry a timestamp: the strip model
            // is reassigned repeatedly while pending drag state settles, which
            // rebuilds every delegate — recreated cards resume the motion from
            // the elapsed time instead of popping into place. Plain
            // displacements (strip shrank / cards shifted) glide without the
            // reveal beat.
            readonly property string topKey: topCard.modelData.isTrailingEmpty
                ? "t"
                : `s${topCard.index}`
            property real introOffset: {
                const plan = root.introPlans[topCard.topKey];
                return plan ? plan.offset : 0;
            }
            property real introOpacity: {
                const plan = root.introPlans[topCard.topKey];
                return plan && plan.fade ? 0 : 1;
            }
            property bool introActive: false
            function startIntroPlan() {
                const plan = root.introPlans[topCard.topKey];
                if (!plan || topCard.introActive)
                    return;
                const pauseMs = plan.fade ? root.topStripIntroPause : 0;
                const slideMs = root.topStripIntroDuration;
                const fadeMs = 300;
                const elapsed = Math.max(0, Date.now() - plan.startAt);
                if (elapsed >= pauseMs + slideMs) {
                    topCard.introOffset = 0;
                    topCard.introOpacity = 1;
                    return;
                }
                if (elapsed <= pauseMs) {
                    topCard.introOffset = plan.offset;
                    topCardIntroPause.duration = Math.max(1, pauseMs - elapsed);
                    topCardIntroOffsetAnimation.duration = slideMs;
                } else {
                    const slideElapsed = elapsed - pauseMs;
                    const progress = Math.min(1, slideElapsed / slideMs);
                    const eased = 1 - Math.pow(1 - progress, 5);
                    topCard.introOffset = plan.offset * (1 - eased);
                    topCardIntroPause.duration = 0;
                    topCardIntroOffsetAnimation.duration = Math.max(1, slideMs - slideElapsed);
                }
                topCard.introOpacity = 1;
                if (plan.fade && elapsed < fadeMs) {
                    topCard.introOpacity = 1 - Math.pow(1 - (elapsed / fadeMs), 3);
                    topCardIntroOpacityAnimation.duration = Math.max(1, fadeMs - elapsed);
                    topCardIntroOpacityAnimation.start();
                }
                topCard.introActive = true;
                topCardIntroSequence.start();
            }
            Component.onCompleted: topCard.startIntroPlan()
            // An existing card can start a plan too (a layout no-op drop only
            // fires the reveal without rebuilding the strip).
            Connections {
                target: root
                function onIntroPlansChanged() {
                    topCard.startIntroPlan();
                }
            }
            SequentialAnimation {
                id: topCardIntroSequence
                onRunningChanged: if (!running) topCard.introActive = false
                PauseAnimation {
                    id: topCardIntroPause
                    duration: 0
                }
                NumberAnimation {
                    id: topCardIntroOffsetAnimation
                    target: topCard
                    property: "introOffset"
                    to: 0
                    duration: root.topStripIntroDuration
                    easing.type: Easing.OutQuint
                }
            }
            NumberAnimation {
                id: topCardIntroOpacityAnimation
                target: topCard
                property: "introOpacity"
                to: 1
                duration: 300
                easing.type: Easing.OutCubic
            }
            opacity: topCard.compactionVisual.opacity * topCard.introOpacity
                * (root.enteringTopCard !== null && topCard.modelData.isTrailingEmpty ? 0 : 1)
            z: (topCard.compactionVisual.active ? 20 + topCard.index : 0)
                + (topCard.introOffset > 0.5 ? 40 : 0)
            transform: [
                Translate {
                    x: topCard.introOffset
                },
                Translate {
                    x: topCard.compactionVisual.x
                    y: topCard.compactionVisual.y
                },
                Rotation {
                    origin.x: topCard.width / 2
                    origin.y: topCard.height / 2
                    angle: topCard.compactionVisual.rotation
                },
                Scale {
                    origin.x: topCard.width / 2
                    origin.y: topCard.height / 2
                    xScale: topCard.compactionVisual.xScale
                    yScale: topCard.compactionVisual.yScale
                }
            ]

            Image {
                anchors.fill: parent
                source: root.wallpaperUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: false
                cache: true
                opacity: topCard.modelData.isTrailingEmpty ? 0.55 : 0.82
            }

            Rectangle {
                anchors.fill: parent
                color: topDrop.containsDrag
                    ? ColorUtils.transparentize(TuiStyle.accent, 0.72)
                    : "transparent"
            }

            // Stable identity: the empty slot is always "N" (a letter, never
            // renumbered); occupied cards carry their real workspace number,
            // which the real-time renumbering keeps consecutive.
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 6
                width: topCardBadgeLabel.implicitWidth + 12
                height: topCardBadgeLabel.implicitHeight + 5
                radius: height / 2
                color: ColorUtils.transparentize(TuiStyle.bg, 0.2)
                border.width: 1
                border.color: topCard.modelData.isTrailingEmpty
                    ? ColorUtils.transparentize(TuiStyle.accent, 0.35)
                    : ColorUtils.transparentize(TuiStyle.fg, 0.6)
                z: 120

                Text {
                    id: topCardBadgeLabel
                    anchors.centerIn: parent
                    // The badge is the card's SLOT number — with real-time
                    // renumbering it matches the workspace id in settled
                    // layouts, and it never flickers when compaction re-keys
                    // ids in place.
                    text: topCard.modelData.isTrailingEmpty
                        ? "N"
                        : String(topCard.index + 1)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: topCard.modelData.isTrailingEmpty
                        ? TuiStyle.accent
                        : TuiStyle.fg
                }
            }

            Item {
                id: topWindowLayer
                anchors.fill: parent
                // Preserve the old direct-delegate stacking order. Without an
                // explicit z the animation wrapper sits below the card-wide
                // MouseArea, so that area consumes presses before windows can
                // start their drag.
                z: 20

                Repeater {
                    model: ScriptModel { values: root.windowAddressesForWorkspace(topCard.modelData.id) }
                    delegate: GalleryWindow {
                        required property string modelData
                        address: modelData
                        galleryRoot: root
                        screen: root.screen
                        sourceWorkspaceId: topCard.modelData.id
                        previewX: 0
                        previewY: 0
                        previewWidth: topCard.width
                        previewHeight: topCard.height
                        closeOnActivate: false
                        interactionEnabled: root.workspaceInteractionEnabled
                        onActivated: root.animateToWorkspace(topCard.modelData.id)
                    }
                }
            }

            TapHandler {
                acceptedButtons: Qt.LeftButton
                gesturePolicy: TapHandler.DragThreshold
                onTapped: root.animateToWorkspace(topCard.modelData.id)
                // 双击进入该工作区；空白槽位双击 = 新建（聚焦首个空工作区）并进入
                onDoubleTapped: {
                    // 双击进入该工作区（空槽卡即新建并进入：卡片编号就是新号）
                    root.activationPending(
                        { workspace: String(Number(topCard.modelData.id)) })
                    root.closeRequested(false)
                }
            }

            DropArea {
                id: topDrop
                anchors.fill: parent
                z: 90
                onEntered: {
                    WorkspaceNavigation.setDragTarget(
                        topCard.modelData.id,
                        topCard.modelData.isTrailingEmpty ?? false,
                        topCard.modelData.monitorName ?? "");
                }
                onExited: WorkspaceNavigation.clearDragTarget(topCard.modelData.id)
            }

            Rectangle {
                anchors.fill: parent
                radius: 0
                color: "transparent"
                border.width: topCard.modelData.id === root.highlightedWorkspaceId ? 4 : 1
                border.color: topCard.modelData.id === root.highlightedWorkspaceId
                    ? TuiStyle.accent
                    : ColorUtils.transparentize(TuiStyle.fg, 0.55)
                z: 100
            }

            Connections {
                target: CrossMonitorDrag
                function onActiveChanged() {
                    if (CrossMonitorDrag.active)
                        root.registerDropTarget(topCard, topCard.modelData);
                }
            }
        }
    }

    // Ghosts of removed strip cards: they replay the card's look at its last
    // position and slide up out of the row (the compaction choreography owns
    // visuals during compaction, so these only cover in-session removals).
    Repeater {
        model: root.exitingTopCards
        delegate: Rectangle {
            id: topGhost
            required property var modelData
            x: topGhost.modelData.x
            y: topList.y
            width: root.topCardWidth
            height: root.topCardHeight
            radius: 10
            clip: true
            z: 500
            color: Appearance.colors.colSurfaceContainerLow
            border.width: 0
            opacity: 1

            Image {
                anchors.fill: parent
                source: root.wallpaperUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: false
                cache: true
                opacity: 0.82
            }

            ParallelAnimation {
                running: true
                NumberAnimation {
                    target: topGhost
                    property: "y"
                    to: topList.y - root.topCardHeight * 0.85
                    duration: root.topStripGhostDuration
                    easing.type: Easing.OutQuart
                }
                NumberAnimation {
                    target: topGhost
                    property: "opacity"
                    to: 0
                    duration: Math.round(root.topStripGhostDuration * 0.88)
                    easing.type: Easing.OutQuart
                }
            }
        }
    }

    // Entering overlay for the empty-slot reveal: a temporary card copies
    // the trailing slot's look, appears half-visible at the screen's right
    // edge, holds for a beat, and glides onto the real (unchanged) card —
    // the strip itself never blinks, rebuilds, or moves.
    Rectangle {
        id: topEntering
        visible: false
        y: topList.y
        width: root.topCardWidth
        height: root.topCardHeight
        radius: 10
        clip: true
        z: 600
        color: Appearance.colors.colSurfaceContainerLow
        border.width: 0
        property real introOffset: 0
        property real introOpacity: 0
        opacity: topEntering.introOpacity
        transform: Translate { x: topEntering.introOffset }

        Image {
            anchors.fill: parent
            source: root.wallpaperUrl
            fillMode: Image.PreserveAspectCrop
            asynchronous: false
            cache: true
            opacity: 0.55
        }

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 6
            width: topEnteringBadgeLabel.implicitWidth + 12
            height: topEnteringBadgeLabel.implicitHeight + 5
            radius: height / 2
            color: ColorUtils.transparentize(TuiStyle.bg, 0.2)
            border.width: 1
            border.color: ColorUtils.transparentize(TuiStyle.accent, 0.35)

            Text {
                id: topEnteringBadgeLabel
                anchors.centerIn: parent
                text: "N"
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: TuiStyle.accent
            }
        }

        function startEntering() {
            const plan = root.enteringTopCard;
            if (!plan)
                return;
            // A new tick may arrive while the previous flight is still
            // running (users re-drop faster than the 1.6 s cycle): stop
            // everything first so the restart isn't ignored or clobbered.
            topEnteringSequence.stop();
            topEnteringOpacityAnimation.stop();
            const x = root.topCardXForIndex(plan.index);
            topEntering.x = x;
            topEntering.introOffset = Math.max(root.topCardWidth * 0.5 + root.cardGap,
                root.width - root.topCardWidth * 0.5 - x);
            topEntering.introOpacity = 0;
            topEntering.visible = true;
            topEnteringPause.duration = root.topStripIntroPause;
            topEnteringOffsetAnimation.duration = root.topStripIntroDuration;
            topEnteringOpacityAnimation.duration = 300;
            topEnteringOpacityAnimation.start();
            topEnteringSequence.start();
        }

        Connections {
            target: root
            function onEnteringTopCardChanged() {
                if (root.enteringTopCard) {
                    topEntering.startEntering();
                } else {
                    topEnteringSequence.stop();
                    topEnteringOpacityAnimation.stop();
                    topEntering.visible = false;
                }
            }
        }

        SequentialAnimation {
            id: topEnteringSequence
            PauseAnimation {
                id: topEnteringPause
                duration: 0
            }
            NumberAnimation {
                id: topEnteringOffsetAnimation
                target: topEntering
                property: "introOffset"
                to: 0
                easing.type: Easing.OutQuint
            }
        }

        NumberAnimation {
            id: topEnteringOpacityAnimation
            target: topEntering
            property: "introOpacity"
            to: 1
            duration: 300
            easing.type: Easing.OutCubic
        }
    }

    Image {
        id: compactionHandoffImage
        x: topList.x
        y: topList.y
        width: topList.width
        height: topList.height
        z: 10000
        source: root.compactionHandoffUrl
        fillMode: Image.Stretch
        smooth: true
        cache: false
        opacity: GlobalStates.overviewCompactionHandoff ? 1 : 0
        visible: source.toString().length > 0 && opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.InOutQuad }
        }
    }

    Item {
        id: bottomViewport
        x: root.bottomCardX
        y: root.bottomCardY
        width: root.bottomCardWidth
        height: root.bottomCardHeight
        clip: true

        Repeater {
            model: root.entries
            delegate: Loader {
                id: pageLoader
                required property var modelData
                required property int index
                readonly property int anchorIndex: root.swipeStartIndex >= 0
                    ? root.swipeStartIndex : root.selectedIndex
                readonly property bool inClickTravelRange: root.clickedWorkspaceId > 0
                    && root.swipeSettling
                    && root.settlementIndex >= 0
                    && index >= Math.min(anchorIndex, root.settlementIndex)
                    && index <= Math.max(anchorIndex, root.settlementIndex)
                x: (index - anchorIndex) * root.pageSpan + root.swipeOffset
                width: bottomViewport.width
                height: bottomViewport.height
                active: inClickTravelRange || Math.abs(index - anchorIndex) <= 1
                asynchronous: false

                sourceComponent: GalleryWorkspacePage {
                    entry: pageLoader.modelData
                    galleryRoot: root
                    screen: root.screen
                    wallpaperUrl: root.wallpaperUrl
                    interactionEnabled: root.workspaceInteractionEnabled
                }
            }
        }
    }

    Rectangle {
        id: dragProxy
        visible: CrossMonitorDrag.active
        x: CrossMonitorDrag.pointerX - root.monitorOriginX - width / 2
        y: CrossMonitorDrag.pointerY - root.monitorOriginY - height / 2
        width: CrossMonitorDrag.compactPreview
            ? Math.max(1, CrossMonitorDrag.sourceWidth / 3)
            : Math.max(110, CrossMonitorDrag.sourceWidth)
        height: CrossMonitorDrag.compactPreview
            ? Math.max(1, CrossMonitorDrag.sourceHeight / 3)
            : Math.max(72, CrossMonitorDrag.sourceHeight)
        z: 20000
        radius: 8
        color: Appearance.colors.colSurfaceContainerLow
        border.width: 2
        border.color: TuiStyle.accent
        opacity: 0.9

        Image {
            anchors.fill: parent
            anchors.margins: 2
            source: CrossMonitorDrag.previewUrl
            fillMode: Image.PreserveAspectCrop
            smooth: true
            cache: false
        }
    }
}
