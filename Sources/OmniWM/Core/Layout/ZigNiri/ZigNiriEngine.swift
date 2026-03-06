import CoreGraphics
import Foundation

final class ZigNiriEngine {
    private struct RuntimeSelectionAnchor {
        let windowId: NodeId?
        let columnId: NodeId?
        let rowIndex: Int?
    }

    private struct RuntimeStateMutationOutcome {
        let rc: Int32
        let applied: Bool
    }

    private var maxVisibleColumns: Int
    private var infiniteLoop: Bool

    private var workspaceViews: [WorkspaceDescriptor.ID: ZigNiriWorkspaceView] = [:]
    private var windowNodeIdsByHandle: [WindowHandle: NodeId] = [:]
    private var windowHandlesByNodeId: [NodeId: WindowHandle] = [:]
    private var windowHandlesByUUID: [UUID: WindowHandle] = [:]

    private var layoutContexts: [WorkspaceDescriptor.ID: NiriLayoutZigKernel.LayoutContext] = [:]

    // Runtime state does not encode these today, so we keep them in Swift side maps.
    private var windowSizingModesByNodeId: [NodeId: SizingMode] = [:]
    private var savedWindowHeightsByNodeId: [NodeId: WeightedSize] = [:]

    private var interactiveMoveState: ZigNiriInteractiveMoveState?
    private var interactiveResizeState: ZigNiriInteractiveResizeState?

    init(
        maxVisibleColumns: Int = 3,
        infiniteLoop: Bool = false
    ) {
        self.maxVisibleColumns = max(1, min(5, maxVisibleColumns))
        self.infiniteLoop = infiniteLoop
    }

    func updateConfiguration(
        maxVisibleColumns: Int? = nil,
        infiniteLoop: Bool? = nil
    ) {
        if let maxVisibleColumns {
            self.maxVisibleColumns = max(1, min(5, maxVisibleColumns))
        }
        if let infiniteLoop {
            self.infiniteLoop = infiniteLoop
        }
    }

    func nodeId(for handle: WindowHandle) -> NodeId? {
        windowNodeIdsByHandle[handle]
    }

    func windowHandle(for nodeId: NodeId) -> WindowHandle? {
        windowHandlesByNodeId[nodeId]
    }

    func workspaceView(for workspaceId: WorkspaceDescriptor.ID) -> ZigNiriWorkspaceView? {
        workspaceViews[workspaceId]
    }

    @discardableResult
    func applyNavigation(
        _ request: ZigNiriNavigationRequest,
        in workspaceId: WorkspaceDescriptor.ID,
        orientation: Monitor.Orientation = .horizontal,
        selection: ZigNiriSelection? = nil
    ) -> ZigNiriNavigationResult {
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return .noChange(
                workspaceId: workspaceId,
                targetNodeId: nil,
                selection: workspaceViews[workspaceId]?.selection
            )
        }

        _ = syncWorkspaceViewFromRuntime(workspaceId: workspaceId)
        var view = ensureWorkspaceView(for: workspaceId)
        if let selection {
            view.selection = selection
        }
        view.selection = normalizedSelection(view.selection, in: view)
        applyFocusState(to: &view)
        workspaceViews[workspaceId] = view

        guard let runtimeRequest = runtimeNavigationRequest(
            for: request,
            orientation: orientation,
            in: view
        )
        else {
            return .noChange(
                workspaceId: workspaceId,
                targetNodeId: view.selection?.selectedNodeId,
                selection: view.selection
            )
        }

        let outcome = NiriStateZigKernel.applyNavigation(
            context: context,
            request: .init(request: runtimeRequest)
        )
        guard outcome.rc == 0 else {
            return .noChange(
                workspaceId: workspaceId,
                targetNodeId: view.selection?.selectedNodeId,
                selection: view.selection
            )
        }

        _ = syncWorkspaceViewFromRuntime(workspaceId: workspaceId)
        var projected = ensureWorkspaceView(for: workspaceId)
        let targetNodeId = outcome.targetWindowId
            ?? navigationFallbackTarget(for: request, in: projected)
            ?? projected.selection?.selectedNodeId

        projected.selection = normalizedSelection(
            ZigNiriSelection(
                selectedNodeId: targetNodeId,
                focusedWindowId: outcome.targetWindowId ?? projected.selection?.focusedWindowId
            ),
            in: projected
        )
        applyFocusState(to: &projected)
        workspaceViews[workspaceId] = projected

        return ZigNiriNavigationResult(
            applied: outcome.applied,
            workspaceId: workspaceId,
            targetNodeId: targetNodeId,
            selection: projected.selection,
            wrapped: false
        )
    }

    @discardableResult
    func applyMutation(
        _ request: ZigNiriMutationRequest,
        in workspaceId: WorkspaceDescriptor.ID,
        selection: ZigNiriSelection? = nil
    ) -> ZigNiriMutationResult {
        guard ensureRuntimeContext(for: workspaceId) != nil else {
            return .noChange(
                workspaceId: workspaceId,
                selection: workspaceViews[workspaceId]?.selection
            )
        }
        _ = syncWorkspaceViewFromRuntime(workspaceId: workspaceId)

        switch request {
        case let .setColumnDisplay(columnId, display):
            return applyColumnDisplayMutation(
                columnId: columnId,
                display: display,
                workspaceId: workspaceId,
                selection: selection
            )

        case let .setWindowSizing(windowId, mode):
            return applyWindowSizingMutation(
                windowId: windowId,
                mode: mode,
                workspaceId: workspaceId,
                selection: selection
            )

        case let .setWindowHeight(windowId, height):
            return applyWindowHeightMutation(
                windowId: windowId,
                height: height,
                workspaceId: workspaceId,
                selection: selection
            )

        case let .removeWindow(windowId):
            return applyRemoveWindowMutation(
                windowId: windowId,
                workspaceId: workspaceId,
                selection: selection
            )

        case .custom:
            var view = ensureWorkspaceView(for: workspaceId)
            if let selection {
                view.selection = normalizedSelection(selection, in: view)
                applyFocusState(to: &view)
                workspaceViews[workspaceId] = view
            }
            return .noChange(workspaceId: workspaceId, selection: view.selection)
        }
    }

    @discardableResult
    func applyWorkspace(
        _ request: ZigNiriWorkspaceRequest,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> ZigNiriMutationResult {
        switch request {
        case .ensureWorkspace:
            let existed = layoutContexts[workspaceId] != nil
            guard ensureRuntimeContext(for: workspaceId) != nil else {
                return .noChange(
                    workspaceId: workspaceId,
                    selection: workspaceViews[workspaceId]?.selection
                )
            }
            _ = syncWorkspaceViewFromRuntime(workspaceId: workspaceId)
            let view = ensureWorkspaceView(for: workspaceId)
            return ZigNiriMutationResult(
                applied: !existed,
                workspaceId: workspaceId,
                selection: view.selection,
                affectedNodeIds: [],
                removedNodeIds: []
            )

        case .clearWorkspace:
            guard let context = ensureRuntimeContext(for: workspaceId) else {
                return .noChange(
                    workspaceId: workspaceId,
                    selection: workspaceViews[workspaceId]?.selection
                )
            }

            let removedIds: [NodeId] = {
                switch NiriStateZigKernel.snapshotRuntimeStateResult(context: context) {
                case let .success(export):
                    return export.windows.map(\.windowId)
                case .failure:
                    return []
                }
            }()

            let resetColumnId = workspaceViews[workspaceId]?.columns.first?.nodeId ?? NodeId()
            let clearedExport = NiriStateZigKernel.RuntimeStateExport(
                columns: [
                    .init(
                        columnId: resetColumnId,
                        windowStart: 0,
                        windowCount: 0,
                        activeTileIdx: 0,
                        isTabbed: false,
                        sizeValue: 1.0
                    ),
                ],
                windows: []
            )

            let rc = NiriStateZigKernel.seedRuntimeState(
                context: context,
                export: clearedExport
            )
            guard rc == 0 else {
                return .noChange(
                    workspaceId: workspaceId,
                    selection: workspaceViews[workspaceId]?.selection
                )
            }

            for removedId in removedIds {
                cleanupWindowMappings(for: removedId)
            }
            _ = syncWorkspaceViewFromRuntime(workspaceId: workspaceId)

            var view = ensureWorkspaceView(for: workspaceId)
            view.selection = nil
            applyFocusState(to: &view)
            workspaceViews[workspaceId] = view

            return ZigNiriMutationResult(
                applied: !removedIds.isEmpty,
                workspaceId: workspaceId,
                selection: nil,
                affectedNodeIds: [],
                removedNodeIds: removedIds
            )

        case let .setSelection(selection):
            guard ensureRuntimeContext(for: workspaceId) != nil else {
                return .noChange(
                    workspaceId: workspaceId,
                    selection: workspaceViews[workspaceId]?.selection
                )
            }
            _ = syncWorkspaceViewFromRuntime(workspaceId: workspaceId)

            var view = ensureWorkspaceView(for: workspaceId)
            view.selection = normalizedSelection(
                selection,
                in: view,
                allowNilWhenRequested: true
            )
            applyFocusState(to: &view)
            workspaceViews[workspaceId] = view

            return ZigNiriMutationResult(
                applied: true,
                workspaceId: workspaceId,
                selection: view.selection,
                affectedNodeIds: [],
                removedNodeIds: []
            )

        case let .moveWindow(windowId, targetWorkspaceId):
            guard let sourceContext = ensureRuntimeContext(for: workspaceId),
                  let targetContext = ensureRuntimeContext(for: targetWorkspaceId)
            else {
                return .noChange(
                    workspaceId: workspaceId,
                    selection: workspaceViews[workspaceId]?.selection
                )
            }

            let outcome = NiriStateZigKernel.applyWorkspace(
                sourceContext: sourceContext,
                targetContext: targetContext,
                request: .init(
                    request: NiriStateZigKernel.WorkspaceRequest(
                        op: .moveWindowToWorkspace,
                        sourceWindowId: windowId,
                        maxVisibleColumns: maxVisibleColumns
                    ),
                    targetCreatedColumnId: UUID(),
                    sourcePlaceholderColumnId: UUID()
                )
            )
            guard outcome.rc == 0 else {
                return .noChange(
                    workspaceId: workspaceId,
                    selection: workspaceViews[workspaceId]?.selection
                )
            }

            _ = syncWorkspaceViewFromRuntime(workspaceId: targetWorkspaceId)
            _ = syncWorkspaceViewFromRuntime(workspaceId: workspaceId)

            let targetView = ensureWorkspaceView(for: targetWorkspaceId)
            return ZigNiriMutationResult(
                applied: outcome.applied,
                workspaceId: targetWorkspaceId,
                selection: targetView.selection,
                affectedNodeIds: [windowId],
                removedNodeIds: []
            )

        case let .moveColumn(columnId, targetWorkspaceId):
            guard let sourceContext = ensureRuntimeContext(for: workspaceId),
                  let targetContext = ensureRuntimeContext(for: targetWorkspaceId)
            else {
                return .noChange(
                    workspaceId: workspaceId,
                    selection: workspaceViews[workspaceId]?.selection
                )
            }

            let outcome = NiriStateZigKernel.applyWorkspace(
                sourceContext: sourceContext,
                targetContext: targetContext,
                request: .init(
                    request: NiriStateZigKernel.WorkspaceRequest(
                        op: .moveColumnToWorkspace,
                        sourceColumnId: columnId
                    ),
                    sourcePlaceholderColumnId: UUID()
                )
            )
            guard outcome.rc == 0 else {
                return .noChange(
                    workspaceId: workspaceId,
                    selection: workspaceViews[workspaceId]?.selection
                )
            }

            _ = syncWorkspaceViewFromRuntime(workspaceId: targetWorkspaceId)
            _ = syncWorkspaceViewFromRuntime(workspaceId: workspaceId)

            let targetView = ensureWorkspaceView(for: targetWorkspaceId)
            return ZigNiriMutationResult(
                applied: outcome.applied,
                workspaceId: targetWorkspaceId,
                selection: targetView.selection,
                affectedNodeIds: [columnId],
                removedNodeIds: []
            )
        }
    }

    @discardableResult
    func syncWindows(
        _ handles: [WindowHandle],
        in workspaceId: WorkspaceDescriptor.ID,
        selectedNodeId: NodeId?,
        focusedHandle: WindowHandle? = nil
    ) -> Set<WindowHandle> {
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return []
        }

        let incomingHandles = Set(handles)
        var incomingByUUID: [UUID: WindowHandle] = [:]
        incomingByUUID.reserveCapacity(handles.count)
        for handle in handles {
            incomingByUUID[handle.id] = handle
            windowHandlesByUUID[handle.id] = handle
        }

        var export: NiriStateZigKernel.RuntimeStateExport
        switch NiriStateZigKernel.snapshotRuntimeStateResult(context: context) {
        case let .success(snapshot):
            export = snapshot
        case .failure:
            export = runtimeBootstrapExport(for: workspaceId)
        }

        var removedNodeIds = Set<NodeId>()
        var keptWindows: [NiriStateZigKernel.RuntimeWindowState] = []
        keptWindows.reserveCapacity(export.windows.count)

        for runtimeWindow in export.windows {
            let mappedHandle = windowHandlesByNodeId[runtimeWindow.windowId]
                ?? incomingByUUID[runtimeWindow.windowId.uuid]

            guard let handle = mappedHandle else {
                removedNodeIds.insert(runtimeWindow.windowId)
                continue
            }

            windowHandlesByNodeId[runtimeWindow.windowId] = handle
            windowNodeIdsByHandle[handle] = runtimeWindow.windowId
            if incomingHandles.contains(handle) {
                keptWindows.append(runtimeWindow)
            } else {
                removedNodeIds.insert(runtimeWindow.windowId)
            }
        }
        export.windows = keptWindows

        if export.columns.isEmpty {
            export.columns = [
                .init(
                    columnId: NodeId(),
                    windowStart: 0,
                    windowCount: 0,
                    activeTileIdx: 0,
                    isTabbed: false,
                    sizeValue: 1.0
                ),
            ]
        }

        let preferredColumnId: NodeId = {
            let view = workspaceViews[workspaceId]
            let anchor = runtimeSelectionAnchor(
                selectedNodeId: selectedNodeId ?? view?.selection?.selectedNodeId,
                in: view
            )
            return anchor?.columnId ?? export.columns.first!.columnId
        }()

        if !export.columns.contains(where: { $0.columnId == preferredColumnId }) {
            export.columns.append(
                .init(
                    columnId: preferredColumnId,
                    windowStart: 0,
                    windowCount: 0,
                    activeTileIdx: 0,
                    isTabbed: false,
                    sizeValue: 1.0
                )
            )
        }

        var existingWindowIds = Set(export.windows.map(\.windowId))
        for handle in handles {
            let nodeId: NodeId
            if let existingNodeId = windowNodeIdsByHandle[handle] {
                nodeId = existingNodeId
            } else {
                nodeId = NodeId(uuid: handle.id)
                windowNodeIdsByHandle[handle] = nodeId
            }
            windowHandlesByNodeId[nodeId] = handle
            windowHandlesByUUID[handle.id] = handle
            if existingWindowIds.contains(nodeId) {
                continue
            }

            export.windows.append(
                NiriStateZigKernel.RuntimeWindowState(
                    windowId: nodeId,
                    columnId: preferredColumnId,
                    columnIndex: 0,
                    sizeValue: 1.0,
                    heightKind: NiriStateZigKernel.heightKindAuto,
                    heightValue: 1.0
                )
            )
            existingWindowIds.insert(nodeId)
        }

        normalizeRuntimeExport(&export)
        let seedRC = NiriStateZigKernel.seedRuntimeState(
            context: context,
            export: export
        )
        guard seedRC == 0 else {
            return []
        }

        let removedHandles = Set(
            removedNodeIds.compactMap { windowHandlesByNodeId[$0] }
        )
        for removedNodeId in removedNodeIds {
            cleanupWindowMappings(for: removedNodeId)
        }

        _ = syncWorkspaceViewFromRuntime(workspaceId: workspaceId)
        var view = ensureWorkspaceView(for: workspaceId)

        let focusedNodeId = focusedHandle.flatMap { windowNodeIdsByHandle[$0] }
        let desiredSelection = ZigNiriSelection(
            selectedNodeId: selectedNodeId ?? view.selection?.selectedNodeId,
            focusedWindowId: focusedNodeId ?? view.selection?.focusedWindowId
        )
        view.selection = normalizedSelection(desiredSelection, in: view)
        applyFocusState(to: &view)
        workspaceViews[workspaceId] = view

        return removedHandles
    }

    func calculateLayout(_ request: ZigNiriLayoutRequest) -> ZigNiriLayoutResult {
        guard let view = workspaceViews[request.workspaceId] else {
            return ZigNiriLayoutResult(frames: [:], hiddenHandles: [:])
        }

        var frames: [WindowHandle: CGRect] = [:]
        for window in view.windowsById.values {
            if let frame = window.frame {
                frames[window.handle] = frame
            }
        }
        return ZigNiriLayoutResult(frames: frames, hiddenHandles: [:])
    }

    func hitTestResize(
        at point: CGPoint,
        _ request: ZigNiriHitTestRequest
    ) -> ZigNiriResizeHitResult? {
        guard let tiled = hitTestTiled(at: point, request) else {
            return nil
        }

        let threshold = max(2.0, 8.0 / max(request.scale, 0.5))
        var edges: ZigNiriResizeEdge = []
        if abs(point.x - tiled.windowFrame.minX) <= threshold {
            edges.insert(.left)
        }
        if abs(point.x - tiled.windowFrame.maxX) <= threshold {
            edges.insert(.right)
        }
        if abs(point.y - tiled.windowFrame.minY) <= threshold {
            edges.insert(.top)
        }
        if abs(point.y - tiled.windowFrame.maxY) <= threshold {
            edges.insert(.bottom)
        }
        guard !edges.isEmpty else {
            return nil
        }

        return ZigNiriResizeHitResult(
            windowHandle: tiled.windowHandle,
            windowId: tiled.windowId,
            columnIndex: tiled.columnIndex,
            edges: edges,
            windowFrame: tiled.windowFrame
        )
    }

    func hitTestTiled(
        at point: CGPoint,
        _ request: ZigNiriHitTestRequest
    ) -> ZigNiriTiledHitResult? {
        guard let view = workspaceViews[request.workspaceId] else {
            return nil
        }

        for (windowId, window) in view.windowsById {
            guard let frame = window.frame else {
                continue
            }
            guard frame.contains(point) else {
                continue
            }
            return ZigNiriTiledHitResult(
                windowHandle: window.handle,
                windowId: windowId,
                columnId: window.columnId,
                columnIndex: columnIndex(for: windowId, in: view),
                windowFrame: frame
            )
        }
        return nil
    }

    @discardableResult
    func beginInteractiveMove(_ state: ZigNiriInteractiveMoveState) -> Bool {
        guard interactiveMoveState == nil else { return false }
        interactiveMoveState = state
        return true
    }

    func updateInteractiveMove(mouseLocation: CGPoint) -> ZigNiriMoveHoverTarget? {
        guard var move = interactiveMoveState else { return nil }
        let hoverTarget: ZigNiriMoveHoverTarget?
        if mouseLocation.x <= move.monitorFrame.minX {
            hoverTarget = .workspaceEdge(side: .left)
        } else if mouseLocation.x >= move.monitorFrame.maxX {
            hoverTarget = .workspaceEdge(side: .right)
        } else {
            hoverTarget = nil
        }
        move.currentHoverTarget = hoverTarget
        interactiveMoveState = move
        return hoverTarget
    }

    func endInteractiveMove(commit: Bool = true) -> ZigNiriMutationResult {
        guard let move = interactiveMoveState else {
            return .noChange(workspaceId: nil, selection: nil)
        }
        defer { interactiveMoveState = nil }

        guard commit else {
            return .noChange(
                workspaceId: move.workspaceId,
                selection: workspaceViews[move.workspaceId]?.selection
            )
        }
        return ZigNiriMutationResult(
            applied: move.currentHoverTarget != nil,
            workspaceId: move.workspaceId,
            selection: workspaceViews[move.workspaceId]?.selection,
            affectedNodeIds: [move.windowId],
            removedNodeIds: []
        )
    }

    @discardableResult
    func beginInteractiveResize(_ state: ZigNiriInteractiveResizeState) -> Bool {
        guard interactiveResizeState == nil else { return false }
        interactiveResizeState = state
        return true
    }

    func updateInteractiveResize(mouseLocation: CGPoint) -> ZigNiriMutationResult {
        guard let resize = interactiveResizeState else {
            return .noChange(workspaceId: nil, selection: nil)
        }
        let hasMovement = mouseLocation != resize.startMouseLocation
        return ZigNiriMutationResult(
            applied: hasMovement,
            workspaceId: resize.workspaceId,
            selection: workspaceViews[resize.workspaceId]?.selection,
            affectedNodeIds: hasMovement ? [resize.windowId] : [],
            removedNodeIds: []
        )
    }

    func endInteractiveResize(commit: Bool = true) -> ZigNiriMutationResult {
        guard let resize = interactiveResizeState else {
            return .noChange(workspaceId: nil, selection: nil)
        }
        defer { interactiveResizeState = nil }

        guard commit else {
            return .noChange(
                workspaceId: resize.workspaceId,
                selection: workspaceViews[resize.workspaceId]?.selection
            )
        }
        return ZigNiriMutationResult(
            applied: true,
            workspaceId: resize.workspaceId,
            selection: workspaceViews[resize.workspaceId]?.selection,
            affectedNodeIds: [resize.windowId],
            removedNodeIds: []
        )
    }
}

private extension ZigNiriEngine {
    func applyColumnDisplayMutation(
        columnId: NodeId,
        display: ColumnDisplay,
        workspaceId: WorkspaceDescriptor.ID,
        selection: ZigNiriSelection?
    ) -> ZigNiriMutationResult {
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }

        let mutation = mutateRuntimeState(context: context) { export in
            guard let columnIndex = export.columns.firstIndex(where: { $0.columnId == columnId }) else {
                return false
            }
            let column = export.columns[columnIndex]
            let isTabbed = display == .tabbed
            guard column.isTabbed != isTabbed else {
                return false
            }

            let nextActiveTile: Int
            if column.windowCount == 0 {
                nextActiveTile = 0
            } else {
                nextActiveTile = min(max(column.activeTileIdx, 0), column.windowCount - 1)
            }

            export.columns[columnIndex] = NiriStateZigKernel.RuntimeColumnState(
                columnId: column.columnId,
                windowStart: column.windowStart,
                windowCount: column.windowCount,
                activeTileIdx: nextActiveTile,
                isTabbed: isTabbed,
                sizeValue: column.sizeValue,
                widthKind: column.widthKind,
                isFullWidth: column.isFullWidth,
                hasSavedWidth: column.hasSavedWidth,
                savedWidthKind: column.savedWidthKind,
                savedWidthValue: column.savedWidthValue
            )
            return true
        }
        guard mutation.rc == 0 else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }

        _ = syncWorkspaceViewFromRuntime(workspaceId: workspaceId)
        var view = ensureWorkspaceView(for: workspaceId)
        if let selection {
            view.selection = normalizedSelection(selection, in: view)
        }
        view.selection = normalizedSelection(view.selection, in: view)
        applyFocusState(to: &view)
        workspaceViews[workspaceId] = view

        return ZigNiriMutationResult(
            applied: mutation.applied,
            workspaceId: workspaceId,
            selection: view.selection,
            affectedNodeIds: mutation.applied ? [columnId] : [],
            removedNodeIds: []
        )
    }

    func applyWindowSizingMutation(
        windowId: NodeId,
        mode: SizingMode,
        workspaceId: WorkspaceDescriptor.ID,
        selection: ZigNiriSelection?
    ) -> ZigNiriMutationResult {
        var view = ensureWorkspaceView(for: workspaceId)
        if let selection {
            view.selection = normalizedSelection(selection, in: view)
        }
        guard var window = view.windowsById[windowId] else {
            return .noChange(workspaceId: workspaceId, selection: view.selection)
        }

        let previousMode = windowSizingModesByNodeId[windowId] ?? window.sizingMode
        guard previousMode != mode else {
            return .noChange(workspaceId: workspaceId, selection: view.selection)
        }

        if previousMode == .normal, mode == .fullscreen {
            savedWindowHeightsByNodeId[windowId] = window.height
        } else if previousMode == .fullscreen,
                  mode == .normal,
                  let savedHeight = savedWindowHeightsByNodeId.removeValue(forKey: windowId)
        {
            _ = setWindowHeightInRuntime(
                windowId: windowId,
                height: savedHeight,
                workspaceId: workspaceId
            )
            _ = syncWorkspaceViewFromRuntime(workspaceId: workspaceId)
            view = ensureWorkspaceView(for: workspaceId)
            guard var refreshedWindow = view.windowsById[windowId] else {
                return .noChange(workspaceId: workspaceId, selection: view.selection)
            }
            refreshedWindow.sizingMode = mode
            view.windowsById[windowId] = refreshedWindow
            window = refreshedWindow
        }

        windowSizingModesByNodeId[windowId] = mode
        window.sizingMode = mode
        view.windowsById[windowId] = window
        view.selection = normalizedSelection(view.selection, in: view)
        applyFocusState(to: &view)
        workspaceViews[workspaceId] = view

        return ZigNiriMutationResult(
            applied: true,
            workspaceId: workspaceId,
            selection: view.selection,
            affectedNodeIds: [windowId],
            removedNodeIds: []
        )
    }

    func applyWindowHeightMutation(
        windowId: NodeId,
        height: WeightedSize,
        workspaceId: WorkspaceDescriptor.ID,
        selection: ZigNiriSelection?
    ) -> ZigNiriMutationResult {
        let mutation = setWindowHeightInRuntime(
            windowId: windowId,
            height: height,
            workspaceId: workspaceId
        )
        guard mutation.rc == 0 else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }

        _ = syncWorkspaceViewFromRuntime(workspaceId: workspaceId)
        var view = ensureWorkspaceView(for: workspaceId)
        if let selection {
            view.selection = normalizedSelection(selection, in: view)
        }
        view.selection = normalizedSelection(view.selection, in: view)
        applyFocusState(to: &view)
        workspaceViews[workspaceId] = view

        return ZigNiriMutationResult(
            applied: mutation.applied,
            workspaceId: workspaceId,
            selection: view.selection,
            affectedNodeIds: mutation.applied ? [windowId] : [],
            removedNodeIds: []
        )
    }

    func applyRemoveWindowMutation(
        windowId: NodeId,
        workspaceId: WorkspaceDescriptor.ID,
        selection: ZigNiriSelection?
    ) -> ZigNiriMutationResult {
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }

        let request = NiriStateZigKernel.MutationRequest(
            op: .removeWindow,
            sourceWindowId: windowId
        )
        let outcome = NiriStateZigKernel.applyMutation(
            context: context,
            request: .init(
                request: request,
                placeholderColumnId: UUID()
            )
        )
        guard outcome.rc == 0 else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }

        if outcome.applied {
            cleanupWindowMappings(for: windowId)
        }

        _ = syncWorkspaceViewFromRuntime(workspaceId: workspaceId)
        var view = ensureWorkspaceView(for: workspaceId)
        if let selection {
            view.selection = normalizedSelection(selection, in: view)
        }
        view.selection = normalizedSelection(view.selection, in: view)
        applyFocusState(to: &view)
        workspaceViews[workspaceId] = view

        return ZigNiriMutationResult(
            applied: outcome.applied,
            workspaceId: workspaceId,
            selection: view.selection,
            affectedNodeIds: [],
            removedNodeIds: outcome.applied ? [windowId] : []
        )
    }

    private func setWindowHeightInRuntime(
        windowId: NodeId,
        height: WeightedSize,
        workspaceId: WorkspaceDescriptor.ID
    ) -> RuntimeStateMutationOutcome {
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return RuntimeStateMutationOutcome(rc: -1, applied: false)
        }

        return mutateRuntimeState(context: context) { export in
            guard let windowIndex = export.windows.firstIndex(where: { $0.windowId == windowId }) else {
                return false
            }

            let runtimeWindow = export.windows[windowIndex]
            let encodedHeight = NiriStateZigKernel.encodeHeight(height)
            let nextSizeValue: Double
            switch height {
            case let .auto(weight):
                nextSizeValue = Double(weight)
            case .fixed:
                nextSizeValue = 1.0
            }

            if runtimeWindow.heightKind == encodedHeight.kind,
               runtimeWindow.heightValue == encodedHeight.value,
               runtimeWindow.sizeValue == nextSizeValue
            {
                return false
            }

            export.windows[windowIndex] = NiriStateZigKernel.RuntimeWindowState(
                windowId: runtimeWindow.windowId,
                columnId: runtimeWindow.columnId,
                columnIndex: runtimeWindow.columnIndex,
                sizeValue: nextSizeValue,
                heightKind: encodedHeight.kind,
                heightValue: encodedHeight.value
            )
            return true
        }
    }

    private func mutateRuntimeState(
        context: NiriLayoutZigKernel.LayoutContext,
        mutate: (inout NiriStateZigKernel.RuntimeStateExport) -> Bool
    ) -> RuntimeStateMutationOutcome {
        var export: NiriStateZigKernel.RuntimeStateExport
        switch NiriStateZigKernel.snapshotRuntimeStateResult(context: context) {
        case let .success(snapshot):
            export = snapshot
        case let .failure(error):
            return RuntimeStateMutationOutcome(rc: error.rc, applied: false)
        }

        let applied = mutate(&export)
        guard applied else {
            return RuntimeStateMutationOutcome(rc: 0, applied: false)
        }

        normalizeRuntimeExport(&export)
        let rc = NiriStateZigKernel.seedRuntimeState(
            context: context,
            export: export
        )
        return RuntimeStateMutationOutcome(rc: rc, applied: rc == 0)
    }

    func ensureWorkspaceView(for workspaceId: WorkspaceDescriptor.ID) -> ZigNiriWorkspaceView {
        if let existing = workspaceViews[workspaceId] {
            return existing
        }
        let view = ZigNiriWorkspaceView(
            workspaceId: workspaceId,
            columns: [],
            windowsById: [:],
            selection: nil
        )
        workspaceViews[workspaceId] = view
        return view
    }

    func ensureRuntimeContext(for workspaceId: WorkspaceDescriptor.ID) -> NiriLayoutZigKernel.LayoutContext? {
        if let context = layoutContexts[workspaceId] {
            return context
        }
        guard let context = NiriLayoutZigKernel.LayoutContext() else {
            return nil
        }
        let bootstrapExport = runtimeBootstrapExport(for: workspaceId)
        let seedRC = NiriStateZigKernel.seedRuntimeState(
            context: context,
            export: bootstrapExport
        )
        guard seedRC == 0 else {
            return nil
        }
        layoutContexts[workspaceId] = context
        return context
    }

    func runtimeBootstrapExport(for workspaceId: WorkspaceDescriptor.ID) -> NiriStateZigKernel.RuntimeStateExport {
        guard let view = workspaceViews[workspaceId], !view.columns.isEmpty else {
            return NiriStateZigKernel.RuntimeStateExport(
                columns: [
                    .init(
                        columnId: NodeId(),
                        windowStart: 0,
                        windowCount: 0,
                        activeTileIdx: 0,
                        isTabbed: false,
                        sizeValue: 1.0
                    ),
                ],
                windows: []
            )
        }

        var runtimeColumns: [NiriStateZigKernel.RuntimeColumnState] = []
        runtimeColumns.reserveCapacity(max(1, view.columns.count))

        var runtimeWindows: [NiriStateZigKernel.RuntimeWindowState] = []
        for (columnIndex, column) in view.columns.enumerated() {
            let start = runtimeWindows.count
            for windowId in column.windowIds {
                guard let window = view.windowsById[windowId] else { continue }
                let encodedHeight = NiriStateZigKernel.encodeHeight(window.height)
                let sizeValue: Double
                switch window.height {
                case let .auto(weight):
                    sizeValue = Double(weight)
                case .fixed:
                    sizeValue = 1.0
                }
                runtimeWindows.append(
                    NiriStateZigKernel.RuntimeWindowState(
                        windowId: window.nodeId,
                        columnId: column.nodeId,
                        columnIndex: columnIndex,
                        sizeValue: sizeValue,
                        heightKind: encodedHeight.kind,
                        heightValue: encodedHeight.value
                    )
                )
            }

            runtimeColumns.append(
                NiriStateZigKernel.RuntimeColumnState(
                    columnId: column.nodeId,
                    windowStart: start,
                    windowCount: runtimeWindows.count - start,
                    activeTileIdx: column.activeWindowIndex ?? 0,
                    isTabbed: column.display == .tabbed,
                    sizeValue: 1.0
                )
            )
        }

        if runtimeColumns.isEmpty {
            runtimeColumns.append(
                .init(
                    columnId: NodeId(),
                    windowStart: 0,
                    windowCount: 0,
                    activeTileIdx: 0,
                    isTabbed: false,
                    sizeValue: 1.0
                )
            )
        }

        return NiriStateZigKernel.RuntimeStateExport(
            columns: runtimeColumns,
            windows: runtimeWindows
        )
    }

    @discardableResult
    func syncWorkspaceViewFromRuntime(workspaceId: WorkspaceDescriptor.ID) -> Bool {
        guard let context = layoutContexts[workspaceId] else {
            return false
        }
        let export: NiriStateZigKernel.RuntimeStateExport
        switch NiriStateZigKernel.snapshotRuntimeStateResult(context: context) {
        case let .success(snapshot):
            export = snapshot
        case .failure:
            return false
        }

        let previousView = workspaceViews[workspaceId]
        var columns: [ZigNiriColumnView] = []
        columns.reserveCapacity(export.columns.count)

        var windowsById: [NodeId: ZigNiriWindowView] = [:]
        windowsById.reserveCapacity(export.windows.count)

        var survivingNodeIds = Set<NodeId>()
        survivingNodeIds.reserveCapacity(export.windows.count)

        for runtimeColumn in export.columns {
            let start = runtimeColumn.windowStart
            let count = runtimeColumn.windowCount

            let runtimeWindows: [NiriStateZigKernel.RuntimeWindowState]
            if start >= 0,
               count >= 0,
               start <= export.windows.count,
               count <= export.windows.count - start
            {
                runtimeWindows = Array(export.windows[start ..< start + count])
            } else {
                runtimeWindows = []
            }

            var columnWindowIds: [NodeId] = []
            columnWindowIds.reserveCapacity(runtimeWindows.count)

            for runtimeWindow in runtimeWindows {
                let handle = windowHandlesByNodeId[runtimeWindow.windowId]
                    ?? windowHandlesByUUID[runtimeWindow.windowId.uuid]
                guard let handle else {
                    continue
                }

                windowHandlesByNodeId[runtimeWindow.windowId] = handle
                windowNodeIdsByHandle[handle] = runtimeWindow.windowId
                windowHandlesByUUID[handle.id] = handle
                survivingNodeIds.insert(runtimeWindow.windowId)

                let priorWindow = previousView?.windowsById[runtimeWindow.windowId]
                let height = NiriStateZigKernel.decodeHeight(
                    kind: runtimeWindow.heightKind,
                    value: runtimeWindow.heightValue
                ) ?? priorWindow?.height ?? .default
                let sizingMode = windowSizingModesByNodeId[runtimeWindow.windowId]
                    ?? priorWindow?.sizingMode
                    ?? .normal

                windowsById[runtimeWindow.windowId] = ZigNiriWindowView(
                    nodeId: runtimeWindow.windowId,
                    handle: handle,
                    columnId: runtimeColumn.columnId,
                    frame: priorWindow?.frame,
                    sizingMode: sizingMode,
                    height: height,
                    isFocused: false
                )
                columnWindowIds.append(runtimeWindow.windowId)
            }

            let activeWindowIndex: Int?
            if columnWindowIds.isEmpty {
                activeWindowIndex = nil
            } else {
                activeWindowIndex = min(max(runtimeColumn.activeTileIdx, 0), columnWindowIds.count - 1)
            }

            columns.append(
                ZigNiriColumnView(
                    nodeId: runtimeColumn.columnId,
                    windowIds: columnWindowIds,
                    display: runtimeColumn.isTabbed ? .tabbed : .normal,
                    activeWindowIndex: activeWindowIndex
                )
            )
        }

        var nextView = ZigNiriWorkspaceView(
            workspaceId: workspaceId,
            columns: columns,
            windowsById: windowsById,
            selection: previousView?.selection
        )
        nextView.selection = normalizedSelection(nextView.selection, in: nextView)
        applyFocusState(to: &nextView)
        workspaceViews[workspaceId] = nextView

        pruneWindowMappings(
            updatedWorkspaceId: workspaceId,
            survivingNodeIds: survivingNodeIds
        )
        return true
    }

    func pruneWindowMappings(
        updatedWorkspaceId: WorkspaceDescriptor.ID,
        survivingNodeIds: Set<NodeId>
    ) {
        var referencedNodeIds = survivingNodeIds
        for (workspaceId, view) in workspaceViews where workspaceId != updatedWorkspaceId {
            referencedNodeIds.formUnion(view.windowsById.keys)
        }

        let knownNodeIds = Array(windowHandlesByNodeId.keys)
        for nodeId in knownNodeIds where !referencedNodeIds.contains(nodeId) {
            cleanupWindowMappings(for: nodeId)
        }
    }

    func normalizeRuntimeExport(_ export: inout NiriStateZigKernel.RuntimeStateExport) {
        var windowsByColumn: [NodeId: [NiriStateZigKernel.RuntimeWindowState]] = [:]
        windowsByColumn.reserveCapacity(export.columns.count + 1)
        for runtimeWindow in export.windows {
            windowsByColumn[runtimeWindow.columnId, default: []].append(runtimeWindow)
        }

        var normalizedColumns: [NiriStateZigKernel.RuntimeColumnState] = []
        normalizedColumns.reserveCapacity(max(1, export.columns.count))
        var normalizedWindows: [NiriStateZigKernel.RuntimeWindowState] = []
        normalizedWindows.reserveCapacity(export.windows.count)

        func appendColumn(_ sourceColumn: NiriStateZigKernel.RuntimeColumnState) {
            let columnWindows = windowsByColumn[sourceColumn.columnId] ?? []
            let start = normalizedWindows.count
            let columnIndex = normalizedColumns.count

            for runtimeWindow in columnWindows {
                normalizedWindows.append(
                    NiriStateZigKernel.RuntimeWindowState(
                        windowId: runtimeWindow.windowId,
                        columnId: sourceColumn.columnId,
                        columnIndex: columnIndex,
                        sizeValue: runtimeWindow.sizeValue,
                        heightKind: runtimeWindow.heightKind,
                        heightValue: runtimeWindow.heightValue
                    )
                )
            }

            let activeTileIdx: Int
            if columnWindows.isEmpty {
                activeTileIdx = 0
            } else {
                activeTileIdx = min(max(sourceColumn.activeTileIdx, 0), columnWindows.count - 1)
            }

            normalizedColumns.append(
                NiriStateZigKernel.RuntimeColumnState(
                    columnId: sourceColumn.columnId,
                    windowStart: start,
                    windowCount: columnWindows.count,
                    activeTileIdx: activeTileIdx,
                    isTabbed: sourceColumn.isTabbed,
                    sizeValue: sourceColumn.sizeValue,
                    widthKind: sourceColumn.widthKind,
                    isFullWidth: sourceColumn.isFullWidth,
                    hasSavedWidth: sourceColumn.hasSavedWidth,
                    savedWidthKind: sourceColumn.savedWidthKind,
                    savedWidthValue: sourceColumn.savedWidthValue
                )
            )
            windowsByColumn.removeValue(forKey: sourceColumn.columnId)
        }

        for sourceColumn in export.columns {
            appendColumn(sourceColumn)
        }

        if !windowsByColumn.isEmpty {
            let orphanColumnIds = windowsByColumn.keys.sorted { lhs, rhs in
                lhs.uuid.uuidString < rhs.uuid.uuidString
            }
            for orphanColumnId in orphanColumnIds {
                appendColumn(
                    NiriStateZigKernel.RuntimeColumnState(
                        columnId: orphanColumnId,
                        windowStart: 0,
                        windowCount: 0,
                        activeTileIdx: 0,
                        isTabbed: false,
                        sizeValue: 1.0
                    )
                )
            }
        }

        if normalizedColumns.isEmpty {
            normalizedColumns.append(
                NiriStateZigKernel.RuntimeColumnState(
                    columnId: NodeId(),
                    windowStart: 0,
                    windowCount: 0,
                    activeTileIdx: 0,
                    isTabbed: false,
                    sizeValue: 1.0
                )
            )
        }

        export.columns = normalizedColumns
        export.windows = normalizedWindows
    }

    func cleanupWindowMappings(for nodeId: NodeId) {
        if let handle = windowHandlesByNodeId.removeValue(forKey: nodeId) {
            windowNodeIdsByHandle.removeValue(forKey: handle)
        }
        windowSizingModesByNodeId.removeValue(forKey: nodeId)
        savedWindowHeightsByNodeId.removeValue(forKey: nodeId)

        if !windowHandlesByNodeId.keys.contains(where: { $0.uuid == nodeId.uuid }) {
            windowHandlesByUUID.removeValue(forKey: nodeId.uuid)
        }
    }

    func normalizedSelection(
        _ selection: ZigNiriSelection?,
        in view: ZigNiriWorkspaceView,
        allowNilWhenRequested: Bool = false
    ) -> ZigNiriSelection? {
        if allowNilWhenRequested, selection == nil {
            return nil
        }
        guard !view.columns.isEmpty || !view.windowsById.isEmpty else {
            return nil
        }

        func containsNode(_ nodeId: NodeId) -> Bool {
            if view.windowsById[nodeId] != nil {
                return true
            }
            return view.columns.contains(where: { $0.nodeId == nodeId })
        }

        let firstWindowId = view.columns.lazy
            .compactMap { $0.windowIds.first }
            .first
            ?? view.windowsById.keys.first

        var selectedNodeId = selection?.selectedNodeId
        if let currentSelectedNodeId = selectedNodeId, !containsNode(currentSelectedNodeId) {
            selectedNodeId = nil
        }
        if selectedNodeId == nil {
            selectedNodeId = firstWindowId ?? view.columns.first?.nodeId
        }

        var focusedWindowId = selection?.focusedWindowId
        if let currentFocusedWindowId = focusedWindowId, view.windowsById[currentFocusedWindowId] == nil {
            focusedWindowId = nil
        }
        if focusedWindowId == nil,
           let selectedNodeId,
           view.windowsById[selectedNodeId] != nil
        {
            focusedWindowId = selectedNodeId
        }
        if focusedWindowId == nil {
            focusedWindowId = firstWindowId
        }

        return ZigNiriSelection(
            selectedNodeId: selectedNodeId,
            focusedWindowId: focusedWindowId
        )
    }

    func applyFocusState(to view: inout ZigNiriWorkspaceView) {
        let focusedWindowId = view.selection?.focusedWindowId
        let windowIds = Array(view.windowsById.keys)
        for windowId in windowIds {
            guard var window = view.windowsById[windowId] else { continue }
            window.isFocused = windowId == focusedWindowId
            view.windowsById[windowId] = window
        }
    }

    private func runtimeSelectionAnchor(
        selectedNodeId: NodeId?,
        in view: ZigNiriWorkspaceView?
    ) -> RuntimeSelectionAnchor? {
        guard let view else { return nil }
        guard let selectedNodeId = selectedNodeId ?? view.selection?.selectedNodeId else {
            if let firstColumn = view.columns.first {
                let firstWindow = firstColumn.windowIds.first
                return RuntimeSelectionAnchor(
                    windowId: firstWindow,
                    columnId: firstColumn.nodeId,
                    rowIndex: firstWindow.flatMap { rowIndex(for: $0, in: firstColumn.windowIds) }
                )
            }
            return nil
        }

        if let window = view.windowsById[selectedNodeId] {
            let row: Int?
            if let columnId = window.columnId,
               let column = view.columns.first(where: { $0.nodeId == columnId })
            {
                row = rowIndex(for: selectedNodeId, in: column.windowIds)
            } else {
                row = nil
            }
            return RuntimeSelectionAnchor(
                windowId: selectedNodeId,
                columnId: window.columnId,
                rowIndex: row
            )
        }

        guard let column = view.columns.first(where: { $0.nodeId == selectedNodeId }) else {
            return nil
        }
        let activeIndex = column.activeWindowIndex ?? 0
        let windowId: NodeId? = {
            if column.windowIds.indices.contains(activeIndex) {
                return column.windowIds[activeIndex]
            }
            return column.windowIds.first
        }()
        return RuntimeSelectionAnchor(
            windowId: windowId,
            columnId: column.nodeId,
            rowIndex: windowId.flatMap { rowIndex(for: $0, in: column.windowIds) }
        )
    }

    func runtimeNavigationRequest(
        for request: ZigNiriNavigationRequest,
        orientation: Monitor.Orientation,
        in view: ZigNiriWorkspaceView
    ) -> NiriStateZigKernel.NavigationRequest? {
        let anchor = runtimeSelectionAnchor(
            selectedNodeId: view.selection?.selectedNodeId,
            in: view
        )

        switch request {
        case let .focus(direction):
            guard let anchor else { return nil }
            return NiriStateZigKernel.NavigationRequest(
                op: .focusTarget,
                sourceWindowId: anchor.windowId,
                sourceColumnId: anchor.columnId,
                direction: direction,
                orientation: orientation,
                infiniteLoop: infiniteLoop
            )

        case let .move(direction):
            guard let anchor else { return nil }
            if let step = direction.primaryStep(for: orientation) {
                return NiriStateZigKernel.NavigationRequest(
                    op: .moveByColumns,
                    sourceWindowId: anchor.windowId,
                    sourceColumnId: anchor.columnId,
                    direction: direction,
                    orientation: orientation,
                    infiniteLoop: infiniteLoop,
                    step: step,
                    targetRowIndex: anchor.rowIndex ?? -1
                )
            }
            if direction.secondaryStep(for: orientation) != nil {
                return NiriStateZigKernel.NavigationRequest(
                    op: .moveVertical,
                    sourceWindowId: anchor.windowId,
                    sourceColumnId: anchor.columnId,
                    direction: direction,
                    orientation: orientation,
                    infiniteLoop: infiniteLoop
                )
            }
            return nil

        case .focusColumnFirst:
            return NiriStateZigKernel.NavigationRequest(
                op: .focusColumnFirst,
                sourceWindowId: anchor?.windowId,
                sourceColumnId: anchor?.columnId
            )

        case .focusColumnLast:
            return NiriStateZigKernel.NavigationRequest(
                op: .focusColumnLast,
                sourceWindowId: anchor?.windowId,
                sourceColumnId: anchor?.columnId
            )

        case let .focusColumn(index):
            return NiriStateZigKernel.NavigationRequest(
                op: .focusColumnIndex,
                sourceWindowId: anchor?.windowId,
                sourceColumnId: anchor?.columnId,
                focusColumnIndex: index
            )

        case let .focusWindow(index):
            guard let anchor else { return nil }
            return NiriStateZigKernel.NavigationRequest(
                op: .focusWindowIndex,
                sourceWindowId: anchor.windowId,
                sourceColumnId: anchor.columnId,
                focusWindowIndex: index
            )
        }
    }

    func navigationFallbackTarget(
        for request: ZigNiriNavigationRequest,
        in view: ZigNiriWorkspaceView
    ) -> NodeId? {
        switch request {
        case .focusColumnFirst:
            guard let column = view.columns.first else { return nil }
            return column.windowIds.first ?? column.nodeId
        case .focusColumnLast:
            guard let column = view.columns.last else { return nil }
            return column.windowIds.last ?? column.nodeId
        case let .focusColumn(index):
            guard view.columns.indices.contains(index) else { return nil }
            let column = view.columns[index]
            return column.windowIds.first ?? column.nodeId
        case let .focusWindow(index):
            let orderedWindowIds = view.columns.flatMap(\.windowIds)
            guard orderedWindowIds.indices.contains(index) else { return nil }
            return orderedWindowIds[index]
        case .focus, .move:
            return view.selection?.selectedNodeId
        }
    }

    func rowIndex(for windowId: NodeId, in windowIds: [NodeId]) -> Int? {
        windowIds.firstIndex(of: windowId)
    }

    func columnIndex(for windowId: NodeId, in view: ZigNiriWorkspaceView) -> Int? {
        view.columns.firstIndex { $0.windowIds.contains(windowId) }
    }
}
