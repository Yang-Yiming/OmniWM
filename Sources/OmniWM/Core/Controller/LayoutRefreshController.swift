import AppKit
import Foundation
import QuartzCore

@MainActor
final class LayoutRefreshController {
    private weak var controller: WMController?

    private var activeRefreshTask: Task<Void, Never>?
    private var isInLightSession: Bool = false
    private var isImmediateLayoutInProgress: Bool = false
    private var refreshTimer: Timer?

    private var displayLinkByDisplayId: [CGDirectDisplayID: CADisplayLink] = [:]
    private var activeDisplayLinkId: CGDirectDisplayID?
    private var scrollAnimationWorkspaceId: WorkspaceDescriptor.ID?
    private var isScrollAnimationRunning: Bool = false
    private var cachedWindowSizes: [Int: CGSize] = [:]
    private var refreshRateByDisplay: [CGDirectDisplayID: Double] = [:]
    private var screenChangeObserver: NSObjectProtocol?

    init(controller: WMController) {
        self.controller = controller
        setupDisplayLinks()
        detectRefreshRates()
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.detectRefreshRates()
                self?.recreateDisplayLinks()
            }
        }
    }

    private func setupDisplayLinks() {
        for screen in NSScreen.screens {
            guard let displayId = screen.displayId else { continue }
            let displayLink = screen.displayLink(target: self, selector: #selector(displayLinkFired(_:)))
            displayLinkByDisplayId[displayId] = displayLink
        }
    }

    private func recreateDisplayLinks() {
        let wasRunning = isScrollAnimationRunning
        let runningWorkspaceId = scrollAnimationWorkspaceId
        if wasRunning { stopScrollAnimation() }

        for (_, displayLink) in displayLinkByDisplayId {
            displayLink.invalidate()
        }
        displayLinkByDisplayId.removeAll()

        setupDisplayLinks()

        if wasRunning, let wsId = runningWorkspaceId {
            startScrollAnimation(for: wsId)
        }
    }

    private func detectRefreshRates() {
        refreshRateByDisplay.removeAll()
        for screen in NSScreen.screens {
            guard let displayId = screen.displayId else { continue }
            if let mode = CGDisplayCopyDisplayMode(displayId) {
                let rate = mode.refreshRate > 0 ? mode.refreshRate : 60.0
                refreshRateByDisplay[displayId] = rate
            } else {
                refreshRateByDisplay[displayId] = 60.0
            }
        }
    }

    func refreshRate(for displayId: CGDirectDisplayID) -> Double {
        refreshRateByDisplay[displayId] ?? 60.0
    }

    @objc private func displayLinkFired(_ displayLink: CADisplayLink) {
        tickScrollAnimation(targetTime: displayLink.targetTimestamp)
    }

    func startScrollAnimation(for workspaceId: WorkspaceDescriptor.ID) {
        scrollAnimationWorkspaceId = workspaceId
        if isScrollAnimationRunning { return }
        isScrollAnimationRunning = true

        guard let controller,
              let monitor = controller.internalWorkspaceManager.monitor(for: workspaceId) else {
            if let mainDisplayId = NSScreen.main?.displayId,
               let displayLink = displayLinkByDisplayId[mainDisplayId] {
                activeDisplayLinkId = mainDisplayId
                displayLink.add(to: .main, forMode: .common)
            }
            return
        }

        let displayId = monitor.id.displayId
        if let displayLink = displayLinkByDisplayId[displayId] {
            activeDisplayLinkId = displayId
            displayLink.add(to: .main, forMode: .common)
        } else if let mainDisplayId = NSScreen.main?.displayId,
                  let displayLink = displayLinkByDisplayId[mainDisplayId] {
            activeDisplayLinkId = mainDisplayId
            displayLink.add(to: .main, forMode: .common)
        }
    }

    func stopScrollAnimation() {
        if let displayId = activeDisplayLinkId,
           let displayLink = displayLinkByDisplayId[displayId] {
            displayLink.remove(from: .main, forMode: .common)
        }
        isScrollAnimationRunning = false
        scrollAnimationWorkspaceId = nil
        activeDisplayLinkId = nil
    }

    private func tickScrollAnimation(targetTime: CFTimeInterval) {
        guard isScrollAnimationRunning else { return }
        guard let controller, let wsId = scrollAnimationWorkspaceId else {
            stopScrollAnimation()
            return
        }
        guard let engine = controller.internalNiriEngine else {
            stopScrollAnimation()
            return
        }

        var state = controller.internalWorkspaceManager.niriViewportState(for: wsId)

        let viewportAnimationRunning = state.tickAnimation(at: targetTime)
        let windowAnimationsRunning = engine.tickAllWindowAnimations(in: wsId, at: targetTime)

        controller.internalWorkspaceManager.updateNiriViewportState(state, for: wsId)
        executeLayoutRefreshImmediate()

        if !viewportAnimationRunning && !windowAnimationsRunning {
            stopScrollAnimation()
        }
    }

    func refreshWindowsAndLayout() {
        scheduleRefreshSession(.timerRefresh)
    }

    func scheduleRefreshSession(_ event: RefreshSessionEvent) {
        guard !isInLightSession else { return }
        activeRefreshTask?.cancel()
        activeRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let baseDebounce = event.debounceInterval
                if baseDebounce > 0 {
                    let mainDisplayId = NSScreen.main?.displayId ?? 0
                    let refreshRate = refreshRateByDisplay[mainDisplayId] ?? 60.0
                    let scaledDebounce = UInt64(Double(baseDebounce) * (60.0 / refreshRate))
                    try await Task.sleep(nanoseconds: scaledDebounce)
                }
                try Task.checkCancellation()
                if event.requiresFullEnumeration {
                    try await executeFullRefresh()
                } else {
                    executeIncrementalRefresh()
                }
            } catch {
                return
            }
        }
    }

    private func executeIncrementalRefresh() {
        guard let controller else { return }

        if controller.internalLockScreenObserver.isFrontmostAppLockScreen() || controller.internalIsLockScreenActive {
            return
        }

        var activeWorkspaceIds: Set<WorkspaceDescriptor.ID> = []
        for monitor in controller.internalWorkspaceManager.monitors {
            if let workspace = controller.internalWorkspaceManager.activeWorkspaceOrFirst(on: monitor.id) {
                activeWorkspaceIds.insert(workspace.id)
            }
        }

        layoutWithNiriEngine(activeWorkspaces: activeWorkspaceIds, useScrollAnimationPath: false)

        if let focusedWorkspaceId = controller.activeWorkspace()?.id {
            controller.ensureFocusedHandleValid(in: focusedWorkspaceId)
        }
    }

    func runLightSession(_ body: () -> Void) {
        activeRefreshTask?.cancel()
        activeRefreshTask = nil
        isInLightSession = true

        if let controller = controller, let engine = controller.internalNiriEngine {
            let focused = controller.internalFocusedHandle
            for monitor in controller.internalWorkspaceManager.monitors {
                if let ws = controller.internalWorkspaceManager.activeWorkspaceOrFirst(on: monitor.id) {
                    let handles = controller.internalWorkspaceManager.entries(in: ws.id).map(\.handle)
                    let selection = controller.internalWorkspaceManager.niriViewportState(for: ws.id).selectedNodeId
                    _ = engine.syncWindows(handles, in: ws.id, selectedNodeId: selection, focusedHandle: focused)
                }
            }
        }

        body()
        isInLightSession = false
        refreshWindowsAndLayout()
    }

    func executeLayoutRefreshImmediate() {
        guard !isImmediateLayoutInProgress else { return }
        guard let controller else { return }
        isImmediateLayoutInProgress = true
        defer { isImmediateLayoutInProgress = false }

        var activeWorkspaceIds: Set<WorkspaceDescriptor.ID> = []
        for monitor in controller.internalWorkspaceManager.monitors {
            if let workspace = controller.internalWorkspaceManager.activeWorkspaceOrFirst(on: monitor.id) {
                activeWorkspaceIds.insert(workspace.id)
            }
        }

        layoutWithNiriEngine(activeWorkspaces: activeWorkspaceIds, useScrollAnimationPath: isScrollAnimationRunning)
    }

    func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshWindowsAndLayout()
            }
        }
        if let timer = refreshTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func resetState() {
        activeRefreshTask?.cancel()
        activeRefreshTask = nil
        isInLightSession = false
        stopScrollAnimation()
        for (_, displayLink) in displayLinkByDisplayId {
            displayLink.invalidate()
        }
        displayLinkByDisplayId.removeAll()
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            screenChangeObserver = nil
        }
    }

    private func executeFullRefresh() async throws {
        guard let controller else { return }
        let interval = signpostInterval("executeLayoutRefresh")
        defer { interval.end() }

        if controller.internalLockScreenObserver.isFrontmostAppLockScreen() || controller.internalIsLockScreenActive {
            return
        }

        let windows = await controller.internalAXManager.currentWindowsAsync()
        try Task.checkCancellation()
        var seenKeys: Set<WindowModel.WindowKey> = []
        let focusedWorkspaceId = controller.activeWorkspace()?.id

        controller.internalWindowStateCache.captureState(
            workspaceManager: controller.internalWorkspaceManager,
            niriEngine: controller.internalNiriEngine
        )

        for (ax, pid, winId) in windows {
            if let bundleId = controller.internalAppInfoCache.bundleId(for: pid) {
                if bundleId == LockScreenObserver.lockScreenAppBundleId {
                    continue
                }
                if controller.internalAppRulesByBundleId[bundleId]?.alwaysFloat == true {
                    continue
                }
            }

            let wsForWindow: WorkspaceDescriptor.ID
            if let cachedWsId = controller.internalWindowStateCache.frozenWorkspaceId(for: winId) {
                wsForWindow = cachedWsId
            } else {
                let defaultWorkspace = controller.resolveWorkspaceForNewWindow(
                    axRef: ax,
                    pid: pid,
                    fallbackWorkspaceId: focusedWorkspaceId
                )
                wsForWindow = controller.workspaceAssignment(pid: pid, windowId: winId) ?? defaultWorkspace
            }

            _ = controller.internalWorkspaceManager.addWindow(ax, pid: pid, windowId: winId, to: wsForWindow)
            seenKeys.insert(.init(pid: pid, windowId: winId))
        }
        controller.internalWorkspaceManager.removeMissing(keys: seenKeys)
        controller.internalWorkspaceManager.garbageCollectUnusedWorkspaces(focusedWorkspaceId: focusedWorkspaceId)

        try Task.checkCancellation()

        var activeWorkspaceIds: Set<WorkspaceDescriptor.ID> = []
        for monitor in controller.internalWorkspaceManager.monitors {
            if let workspace = controller.internalWorkspaceManager.activeWorkspaceOrFirst(on: monitor.id) {
                activeWorkspaceIds.insert(workspace.id)
            }
        }

        layoutWithNiriEngine(activeWorkspaces: activeWorkspaceIds, useScrollAnimationPath: false)

        if let focusedWorkspaceId {
            controller.ensureFocusedHandleValid(in: focusedWorkspaceId)
        }
    }

    func layoutWithNiriEngine(activeWorkspaces: Set<WorkspaceDescriptor.ID>, useScrollAnimationPath: Bool = false) {
        guard let controller else { return }
        guard let engine = controller.internalNiriEngine else { return }
        let workspaceManager = controller.internalWorkspaceManager

        let cornersByMonitor = CornerHidingService.calculateOptimalCorners(for: workspaceManager.monitors)

        for monitor in workspaceManager.monitors {
            guard let workspace = workspaceManager.activeWorkspaceOrFirst(on: monitor.id) else { continue }
            unhideWorkspace(workspace.id, monitor: monitor)
        }

        for monitor in workspaceManager.monitors {
            guard let workspace = workspaceManager.activeWorkspaceOrFirst(on: monitor.id) else { continue }
            let wsId = workspace.id

            let windowHandles = workspaceManager.entries(in: wsId).map(\.handle)
            let existingHandleIds = Set(engine.root(for: wsId)?.allWindows.map(\.handle.id) ?? [])
            let currentSelection = workspaceManager.niriViewportState(for: wsId).selectedNodeId
            _ = engine.syncWindows(windowHandles, in: wsId, selectedNodeId: currentSelection, focusedHandle: controller.internalFocusedHandle)
            let newHandles = windowHandles.filter { !existingHandleIds.contains($0.id) }

            for entry in workspaceManager.entries(in: wsId) {
                let currentSize = (try? AXWindowService.frame(entry.axRef))?.size
                var constraints = AXWindowService.sizeConstraints(entry.axRef, currentSize: currentSize)

                if let bundleId = controller.internalAppInfoCache.bundleId(for: entry.handle.pid),
                   let rule = controller.internalAppRulesByBundleId[bundleId]
                {
                    if let minW = rule.minWidth {
                        constraints.minSize.width = max(constraints.minSize.width, minW)
                    }
                    if let minH = rule.minHeight {
                        constraints.minSize.height = max(constraints.minSize.height, minH)
                    }
                }

                engine.updateWindowConstraints(for: entry.handle, constraints: constraints)
            }

            var state = workspaceManager.niriViewportState(for: wsId)
            state.displayRefreshRate = refreshRateByDisplay[monitor.id.displayId] ?? 60.0

            if let selectedId = state.selectedNodeId {
                if engine.findNode(by: selectedId) == nil {
                    state.selectedNodeId = engine.validateSelection(selectedId, in: wsId)
                }
            }

            if state.selectedNodeId == nil {
                if let firstHandle = windowHandles.first,
                   let firstNode = engine.findNode(for: firstHandle)
                {
                    state.selectedNodeId = firstNode.id
                }
            }

            if let selectedId = state.selectedNodeId,
               let selectedNode = engine.findNode(by: selectedId) as? NiriWindow
            {
                controller.internalLastFocusedByWorkspace[wsId] = selectedNode.handle
                if let currentFocused = controller.internalFocusedHandle {
                    if workspaceManager.workspace(for: currentFocused) == wsId {
                        controller.internalFocusedHandle = selectedNode.handle
                    }
                } else {
                    controller.internalFocusedHandle = selectedNode.handle
                }
            }

            let gaps = LayoutGaps(
                horizontal: CGFloat(workspaceManager.gaps),
                vertical: CGFloat(workspaceManager.gaps),
                outer: workspaceManager.outerGaps
            )

            let insetFrame = controller.insetWorkingFrame(from: monitor.visibleFrame)
            let area = WorkingAreaContext(
                workingFrame: insetFrame,
                viewFrame: monitor.frame,
                scale: backingScale(for: monitor)
            )

            var frames = engine.calculateCombinedLayout(
                in: wsId,
                monitor: monitor,
                gaps: gaps,
                state: state,
                workingArea: area
            )

            if let newHandle = newHandles.last,
               let newNode = engine.findNode(for: newHandle),
               wsId == controller.activeWorkspace()?.id
            {
                state.selectedNodeId = newNode.id
                let gap = CGFloat(workspaceManager.gaps)
                engine.ensureSelectionVisible(
                    node: newNode,
                    in: wsId,
                    state: &state,
                    edge: .right,
                    workingFrame: insetFrame,
                    gaps: gap
                )
                controller.internalFocusedHandle = newHandle
                controller.internalLastFocusedByWorkspace[wsId] = newHandle
                engine.updateFocusTimestamp(for: newNode.id)
                workspaceManager.updateNiriViewportState(state, for: wsId)
                startScrollAnimation(for: wsId)
                controller.focusWindow(newHandle)

                frames = engine.calculateCombinedLayout(
                    in: wsId,
                    monitor: monitor,
                    gaps: gaps,
                    state: state,
                    workingArea: area
                )
            }

            let hiddenHandles = engine.hiddenWindowHandles(in: wsId, state: state, workingFrame: insetFrame)
            let corner = cornersByMonitor[monitor.id] ?? .bottomRightCorner

            for entry in workspaceManager.entries(in: wsId) {
                if hiddenHandles.contains(entry.handle) {
                    hideWindow(entry, monitor: monitor, corner: corner)
                } else {
                    unhideWindow(entry, monitor: monitor)
                }
            }

            var frameUpdates: [(pid: pid_t, windowId: Int, frame: CGRect)] = []
            var positionOnlyUpdates: [(windowId: Int, origin: CGPoint)] = []
            var needsFullUpdate = false

            for (handle, frame) in frames {
                if hiddenHandles.contains(handle) { continue }
                if let entry = workspaceManager.entry(for: handle) {
                    frameUpdates.append((handle.pid, entry.windowId, frame))

                    if useScrollAnimationPath {
                        if let cachedSize = cachedWindowSizes[entry.windowId],
                           abs(cachedSize.width - frame.size.width) < 1 &&
                           abs(cachedSize.height - frame.size.height) < 1
                        {
                            positionOnlyUpdates.append((entry.windowId, frame.origin))
                        } else {
                            needsFullUpdate = true
                        }
                    }
                    cachedWindowSizes[entry.windowId] = frame.size
                }
            }

            if useScrollAnimationPath && !needsFullUpdate && !positionOnlyUpdates.isEmpty {
                controller.internalAXManager.applyPositionsViaSkyLight(positionOnlyUpdates)
            } else {
                controller.internalAXManager.applyFramesParallel(frameUpdates)
            }

            if let focusedHandle = controller.internalFocusedHandle {
                if hiddenHandles.contains(focusedHandle) {
                    controller.internalBorderManager.hideBorder()
                } else if let frame = frames[focusedHandle],
                          let entry = workspaceManager.entry(for: focusedHandle)
                {
                    controller.updateBorderIfAllowed(handle: focusedHandle, frame: frame, windowId: entry.windowId)
                }
            }

            workspaceManager.updateNiriViewportState(state, for: wsId)
        }

        updateTabbedColumnOverlays()
        controller.updateWorkspaceBar()

        for ws in workspaceManager.workspaces where !activeWorkspaces.contains(ws.id) {
            guard let monitor = workspaceManager.monitor(for: ws.id) else { continue }
            guard let corner = cornersByMonitor[monitor.id] else { continue }
            hideWorkspace(ws.id, monitor: monitor, corner: corner)
        }
    }

    private func backingScale(for monitor: Monitor) -> CGFloat {
        NSScreen.screens.first(where: { $0.displayId == monitor.id.displayId })?.backingScaleFactor ?? 2.0
    }

    private func unhideWorkspace(_ workspaceId: WorkspaceDescriptor.ID, monitor: Monitor) {
        guard let controller else { return }
        for entry in controller.internalWorkspaceManager.entries(in: workspaceId) {
            unhideWindow(entry, monitor: monitor)
        }
    }

    private func hideWorkspace(_ workspaceId: WorkspaceDescriptor.ID, monitor: Monitor, corner: OptimalHideCorner) {
        guard let controller else { return }
        for entry in controller.internalWorkspaceManager.entries(in: workspaceId) {
            hideWindow(entry, monitor: monitor, corner: corner)
        }
    }

    private func hideWindow(_ entry: WindowModel.Entry, monitor: Monitor, corner: OptimalHideCorner) {
        guard let controller else { return }
        guard let frame = try? AXWindowService.frame(entry.axRef) else { return }
        if !controller.internalWorkspaceManager.isHiddenInCorner(entry.handle) {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let referenceFrame = center.monitorApproximation(in: controller.internalWorkspaceManager.monitors)?
                .frame ?? monitor.frame
            let proportional = proportionalPosition(topLeft: frame.topLeftCorner, in: referenceFrame)
            controller.internalWorkspaceManager.setHiddenProportionalPosition(proportional, for: entry.handle)
        }
        let origin = hiddenOrigin(for: frame.size, monitor: monitor, corner: corner, pid: entry.handle.pid)
        try? AXWindowService.setFrame(entry.axRef, frame: CGRect(origin: origin, size: frame.size))
    }

    private func unhideWindow(_ entry: WindowModel.Entry, monitor _: Monitor) {
        guard let controller else { return }
        controller.internalWorkspaceManager.setHiddenProportionalPosition(nil, for: entry.handle)
    }

    private func proportionalPosition(topLeft: CGPoint, in frame: CGRect) -> CGPoint {
        let width = max(1, frame.width)
        let height = max(1, frame.height)
        let x = (topLeft.x - frame.minX) / width
        let y = (frame.maxY - topLeft.y) / height
        return CGPoint(x: min(max(0, x), 1), y: min(max(0, y), 1))
    }

    private func hiddenOrigin(
        for size: CGSize,
        monitor: Monitor,
        corner: OptimalHideCorner,
        pid: pid_t
    ) -> CGPoint {
        let visible = monitor.visibleFrame
        let offset: CGFloat = isZoomApp(pid) ? 0 : 1
        switch corner {
        case .bottomLeftCorner:
            return CGPoint(x: visible.minX - size.width + offset, y: visible.minY + offset - size.height)
        case .bottomRightCorner:
            return CGPoint(x: visible.maxX - offset, y: visible.minY + offset - size.height)
        }
    }

    private func isZoomApp(_ pid: pid_t) -> Bool {
        controller?.internalAppInfoCache.bundleId(for: pid) == "us.zoom.xos"
    }

    func updateTabbedColumnOverlays() {
        guard let controller else { return }
        guard let engine = controller.internalNiriEngine else {
            controller.internalTabbedOverlayManager.removeAll()
            return
        }

        var infos: [TabbedColumnOverlayInfo] = []
        for monitor in controller.internalWorkspaceManager.monitors {
            guard let workspace = controller.internalWorkspaceManager.activeWorkspaceOrFirst(on: monitor.id)
            else { continue }

            for column in engine.columns(in: workspace.id) where column.isTabbed {
                guard let frame = column.frame else { continue }
                guard TabbedColumnOverlayManager.shouldShowOverlay(
                    columnFrame: frame,
                    visibleFrame: monitor.visibleFrame
                ) else { continue }

                let windows = column.windowNodes
                guard !windows.isEmpty else { continue }

                let activeIndex = min(max(0, column.activeTileIdx), windows.count - 1)
                let activeHandle = windows[activeIndex].handle
                let activeWindowId = controller.internalWorkspaceManager.entry(for: activeHandle)?.windowId

                infos.append(
                    TabbedColumnOverlayInfo(
                        workspaceId: workspace.id,
                        columnId: column.id,
                        columnFrame: frame,
                        tabCount: windows.count,
                        activeIndex: activeIndex,
                        activeWindowId: activeWindowId
                    )
                )
            }
        }

        controller.internalTabbedOverlayManager.updateOverlays(infos)
    }

    func selectTabInNiri(workspaceId: WorkspaceDescriptor.ID, columnId: NodeId, index: Int) {
        guard let controller else { return }
        guard let engine = controller.internalNiriEngine else { return }
        guard let column = engine.columns(in: workspaceId).first(where: { $0.id == columnId }) else { return }

        let windows = column.windowNodes
        guard windows.indices.contains(index) else { return }

        column.setActiveTileIdx(index)
        engine.updateTabbedColumnVisibility(column: column)

        let target = windows[index]
        var state = controller.internalWorkspaceManager.niriViewportState(for: workspaceId)
        state.selectedNodeId = target.id
        if let monitor = controller.internalWorkspaceManager.monitor(for: workspaceId) {
            let gap = CGFloat(controller.internalWorkspaceManager.gaps)
            engine.ensureSelectionVisible(
                node: target,
                in: workspaceId,
                state: &state,
                edge: .left,
                workingFrame: monitor.visibleFrame,
                gaps: gap
            )
        }
        controller.internalWorkspaceManager.updateNiriViewportState(state, for: workspaceId)

        controller.internalFocusedHandle = target.handle
        engine.updateFocusTimestamp(for: target.id)
        controller.focusWindow(target.handle)
        updateTabbedColumnOverlays()
    }
}
