import AppKit
import Foundation

extension WMController {
    func axEventSetup() {
        CGSEventObserver.shared.delegate = self
        CGSEventObserver.shared.start()
    }

    func axEventCleanup() {
        CGSEventObserver.shared.delegate = nil
    }
}

extension WMController: CGSEventDelegate {
    func cgsEventObserver(_: CGSEventObserver, didReceive event: CGSWindowEvent) {
        switch event {
        case let .created(windowId, _):
            handleCGSWindowCreated(windowId: windowId)

        case let .destroyed(windowId, _):
            handleCGSWindowDestroyed(windowId: windowId)

        case let .closed(windowId):
            handleCGSWindowDestroyed(windowId: windowId)

        case let .moved(windowId):
            handleWindowMoveOrResize(windowId: windowId)
            scheduleRefreshSession(.axWindowChanged)

        case let .resized(windowId):
            handleWindowMoveOrResize(windowId: windowId)
            scheduleRefreshSession(.axWindowChanged)

        case let .frontAppChanged(pid):
            handleAppActivation(pid: pid)

        case .titleChanged:
            updateWorkspaceBar()
        }
    }

    private func handleCGSWindowCreated(windowId: UInt32) {
        if isDiscoveryInProgress {
            return
        }

        if workspaceManager.entry(forWindowId: Int(windowId)) != nil {
            return
        }

        guard let windowInfo = SkyLight.shared.queryWindowInfo(windowId) else {
            return
        }

        let pid = windowInfo.pid
        CGSEventObserver.shared.subscribeToWindows([windowId])

        if let axRef = AXWindowService.axWindowRef(for: windowId, pid: pid) {
            handleCreated(ref: axRef, pid: pid, winId: Int(windowId))
        }
    }

    private func handleWindowMoveOrResize(windowId: UInt32) {
        guard let focusedHandle,
              let entry = workspaceManager.entry(for: focusedHandle),
              entry.windowId == Int(windowId)
        else { return }

        if let frame = try? AXWindowService.frame(entry.axRef) {
            updateBorderIfAllowed(handle: focusedHandle, frame: frame, windowId: Int(windowId))
        }
    }

    private func handleCGSWindowDestroyed(windowId: UInt32) {
        guard let entry = workspaceManager.entry(
            forWindowId: Int(windowId),
            inVisibleWorkspaces: true
        ) else {
            return
        }

        handleRemoved(pid: entry.handle.pid, winId: Int(windowId))
    }

    func subscribeToManagedWindows() {
        let windowIds = workspaceManager.allEntries().compactMap { entry -> UInt32? in
            UInt32(entry.windowId)
        }
        CGSEventObserver.shared.subscribeToWindows(windowIds)
    }

    private func handleCreated(ref: AXWindowRef, pid: pid_t, winId: Int) {
        let app = NSRunningApplication(processIdentifier: pid)
        let bundleId = app?.bundleIdentifier
        let appPolicy = app?.activationPolicy
        let windowType = AXWindowService.windowType(ref, appPolicy: appPolicy, bundleId: bundleId)
        guard windowType == .tiling else { return }

        if let bundleId, appRulesByBundleId[bundleId]?.alwaysFloat == true {
            return
        }

        let workspaceId = resolveWorkspaceForNewWindow(
            axRef: ref,
            pid: pid,
            fallbackWorkspaceId: activeWorkspace()?.id
        )

        if workspaceId != activeWorkspace()?.id {
            if let monitor = workspaceManager.monitor(for: workspaceId),
               workspaceManager.workspaces(on: monitor.id)
               .contains(where: { $0.id == workspaceId })
            {
                if let currentMonitorId = activeMonitorId ?? monitorForInteraction()?.id,
                    currentMonitorId != monitor.id
                {
                    previousMonitorId = currentMonitorId
                }
                activeMonitorId = monitor.id
                _ = workspaceManager.setActiveWorkspace(workspaceId, on: monitor.id)
            }
        }

        _ = workspaceManager.addWindow(ref, pid: pid, windowId: winId, to: workspaceId)
        CGSEventObserver.shared.subscribeToWindows([UInt32(winId)])
        updateWorkspaceBar()

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let app = NSRunningApplication(processIdentifier: pid) {
                _ = await axManager.windowsForApp(app)
            }
        }

        scheduleRefreshSession(.axWindowCreated)
    }

    func handleRemoved(pid: pid_t, winId: Int) {
        let entry = workspaceManager.entry(forPid: pid, windowId: winId)
        let affectedWorkspaceId = entry?.workspaceId
        let removedHandle = entry?.handle

        if let entry,
           let wsId = affectedWorkspaceId,
           let monitor = workspaceManager.monitor(for: wsId),
           workspaceManager.activeWorkspace(on: monitor.id)?.id == wsId,
           settings.animationsEnabled,
           let workspaceName = workspaceManager.descriptor(for: wsId)?.name,
           settings.layoutType(for: workspaceName) != .dwindle
        {
            let shouldAnimate = if let engine = niriEngine,
                                    let windowNode = engine.findNode(for: entry.handle)
            {
                !windowNode.isHiddenInTabbedMode
            } else {
                true
            }
            if shouldAnimate {
                startWindowCloseAnimation(
                    entry: entry,
                    monitor: monitor
                )
            }
        }

        let needsFocusRecovery = removedHandle?.id == focusedHandle?.id

        if let removed = removedHandle {
            focusManager.handleWindowRemoved(removed, in: affectedWorkspaceId)
        }

        var oldFrames: [WindowHandle: CGRect] = [:]
        var removedNodeId: NodeId?
        if let wsId = affectedWorkspaceId, let engine = niriEngine {
            oldFrames = engine.captureWindowFrames(in: wsId)
            if let handle = removedHandle {
                removedNodeId = engine.findNode(for: handle)?.id
            }
        }

        workspaceManager.removeWindow(pid: pid, windowId: winId)

        if needsFocusRecovery, let wsId = affectedWorkspaceId {
            focusManager.ensureFocusedHandleValid(
                in: wsId,
                engine: niriEngine,
                workspaceManager: workspaceManager,
                focusWindowAction: { [weak self] handle in self?.focusWindow(handle) }
            )
        }

        if let wsId = affectedWorkspaceId {
            Task { @MainActor [weak self] in
                guard let self else { return }

                await layoutWithNiriEngine(
                    activeWorkspaces: [wsId],
                    useScrollAnimationPath: true,
                    removedNodeId: removedNodeId
                )

                if let engine = niriEngine {
                    let newFrames = engine.captureWindowFrames(in: wsId)
                    let animationsTriggered = engine.triggerMoveAnimations(
                        in: wsId,
                        oldFrames: oldFrames,
                        newFrames: newFrames
                    )
                    let hasWindowAnimations = engine.hasAnyWindowAnimationsRunning(in: wsId)
                    let hasColumnAnimations = engine.hasAnyColumnAnimationsRunning(in: wsId)

                    if animationsTriggered || hasWindowAnimations || hasColumnAnimations {
                        startScrollAnimation(for: wsId)
                    }
                }
            }
        }

        if let focused = focusedHandle,
           let entry = workspaceManager.entry(for: focused),
           let frame = try? AXWindowService.frame(entry.axRef)
        {
            updateBorderIfAllowed(handle: focused, frame: frame, windowId: entry.windowId)
        } else {
            borderManager.hideBorder()
        }
    }

    func handleAppActivation(pid: pid_t) {
        guard hasStartedServices else { return }
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)

        guard result == .success, let windowElement = focusedWindow else {
            focusManager.setNonManagedFocus(active: true)
            focusManager.setAppFullscreen(active: false)
            borderManager.hideBorder()
            return
        }

        guard let axRef = try? AXWindowRef(element: windowElement as! AXUIElement) else {
            focusManager.setNonManagedFocus(active: true)
            focusManager.setAppFullscreen(active: false)
            borderManager.hideBorder()
            return
        }
        let winId = axRef.windowId

        if let entry = workspaceManager.entry(forPid: pid, windowId: winId) {
            let wsId = entry.workspaceId
            focusManager.setNonManagedFocus(active: false)

            let targetMonitor = workspaceManager.monitor(for: wsId)
            let isWorkspaceActive = targetMonitor.map { monitor in
                workspaceManager.activeWorkspace(on: monitor.id)?.id == wsId
            } ?? false

            if !isWorkspaceActive {
                let wsName = workspaceManager.descriptor(for: wsId)?.name ?? ""
                if let result = workspaceManager.focusWorkspace(named: wsName) {
                    let currentMonitorId = activeMonitorId
                        ?? monitorForInteraction()?.id
                    if let currentMonitorId, currentMonitorId != result.monitor.id {
                        previousMonitorId = currentMonitorId
                    }
                    activeMonitorId = result.monitor.id
                    syncMonitorsToNiriEngine()
                }
            }

            focusManager.setFocus(entry.handle, in: wsId)

            if let engine = niriEngine,
               let node = engine.findNode(for: entry.handle),
               let _ = workspaceManager.monitor(for: wsId)
            {
                var state = workspaceManager.niriViewportState(for: wsId)
                activateNode(
                    node, in: wsId, state: &state,
                    options: .init(layoutRefresh: isWorkspaceActive, axFocus: false)
                )

                if let frame = node.frame {
                    updateBorderIfAllowed(handle: entry.handle, frame: frame, windowId: entry.windowId)
                } else if let frame = try? AXWindowService.frame(entry.axRef) {
                    updateBorderIfAllowed(handle: entry.handle, frame: frame, windowId: entry.windowId)
                }
            } else if let frame = try? AXWindowService.frame(entry.axRef) {
                updateBorderIfAllowed(handle: entry.handle, frame: frame, windowId: entry.windowId)
            }
            updateTabbedColumnOverlays()
            if !isWorkspaceActive {
                refreshWindowsAndLayout()
                focusWindow(entry.handle)
            }
            return
        }

        focusManager.setNonManagedFocus(active: true)
        focusManager.setAppFullscreen(active: false)
        borderManager.hideBorder()
    }

    func handleAppHidden(pid: pid_t) {
        hiddenAppPIDs.insert(pid)

        for entry in workspaceManager.entries(forPid: pid) {
            workspaceManager.setLayoutReason(.macosHiddenApp, for: entry.handle)
        }
        scheduleRefreshSession(.appHidden)
    }

    func handleAppUnhidden(pid: pid_t) {
        hiddenAppPIDs.remove(pid)

        for entry in workspaceManager.entries(forPid: pid) {
            if workspaceManager.layoutReason(for: entry.handle) == .macosHiddenApp {
                _ = workspaceManager.restoreFromNativeState(for: entry.handle)
            }
        }
        scheduleRefreshSession(.appUnhidden)
    }

    func focusWindow(_ handle: WindowHandle) {
        guard let entry = workspaceManager.entry(for: handle) else { return }
        focusManager.setNonManagedFocus(active: false)

        let axRef = entry.axRef
        let pid = handle.pid
        let windowId = entry.windowId
        let moveMouseEnabled = moveMouseToFocusedWindowEnabled

        focusManager.focusWindow(
            handle,
            workspaceId: entry.workspaceId,
            performFocus: { [weak self] in
                OmniWM.focusWindow(pid: pid, windowId: UInt32(windowId), windowRef: axRef.element)
                AXUIElementPerformAction(axRef.element, kAXRaiseAction as CFString)

                if let runningApp = NSRunningApplication(processIdentifier: pid) {
                    runningApp.activate()
                }

                guard let self else { return }

                if moveMouseEnabled {
                    self.moveMouseToWindow(handle)
                }

                if let entry = self.workspaceManager.entry(for: handle) {
                    if let engine = self.niriEngine,
                       let node = engine.findNode(for: handle),
                       let frame = node.frame
                    {
                        self.updateBorderIfAllowed(handle: entry.handle, frame: frame, windowId: entry.windowId)
                    } else if let frame = try? AXWindowService.frame(entry.axRef) {
                        self.updateBorderIfAllowed(handle: entry.handle, frame: frame, windowId: entry.windowId)
                    }
                }
            },
            onDeferredFocus: { [weak self] deferred in
                guard let self, self.workspaceManager.entry(for: deferred) != nil else { return }
                self.focusWindow(deferred)
            }
        )
    }


    func updateBorderIfAllowed(handle: WindowHandle, frame: CGRect, windowId: Int) {
        guard let activeWs = activeWorkspace(),
              workspaceManager.workspace(for: handle) == activeWs.id
        else {
            borderManager.hideBorder()
            return
        }

        if focusManager.isNonManagedFocusActive {
            borderManager.hideBorder()
            return
        }

        if shouldDeferBorderUpdates(for: activeWs.id) {
            borderManager.hideBorder()
            return
        }

        if let entry = workspaceManager.entry(for: handle) {
            focusManager.setAppFullscreen(active: AXWindowService.isFullscreen(entry.axRef))
        } else {
            focusManager.setAppFullscreen(active: false)
        }

        if focusManager.isAppFullscreenActive || isManagedWindowFullscreen(handle) {
            borderManager.hideBorder()
            return
        }
        borderManager.updateFocusedWindow(frame: frame, windowId: windowId)
    }

    private func shouldDeferBorderUpdates(for workspaceId: WorkspaceDescriptor.ID) -> Bool {
        let state = workspaceManager.niriViewportState(for: workspaceId)
        if state.viewOffsetPixels.isAnimating {
            return true
        }

        if hasDwindleAnimationRunning(in: workspaceId) {
            return true
        }

        guard let engine = niriEngine else { return false }
        if engine.hasAnyWindowAnimationsRunning(in: workspaceId) {
            return true
        }
        if engine.hasAnyColumnAnimationsRunning(in: workspaceId) {
            return true
        }
        return false
    }

    private func isManagedWindowFullscreen(_ handle: WindowHandle) -> Bool {
        guard let engine = niriEngine,
              let windowNode = engine.findNode(for: handle)
        else {
            return false
        }
        return windowNode.isFullscreen
    }
}
