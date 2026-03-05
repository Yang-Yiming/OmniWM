import Foundation

enum NiriStateZigRuntimeSnapshotApplier {
    struct ProjectionResult {
        let applied: Bool
        let failureReason: String?
    }

    static func project(
        export: NiriStateZigKernel.RuntimeStateExport,
        workspaceId: WorkspaceDescriptor.ID,
        engine: NiriLayoutEngine
    ) -> ProjectionResult {
        projectInternal(
            export: export,
            workspaceId: workspaceId,
            engine: engine,
            additionalHandlesById: [:]
        )
    }

    static func projectLifecycle(
        export: NiriStateZigKernel.RuntimeStateExport,
        workspaceId: WorkspaceDescriptor.ID,
        engine: NiriLayoutEngine,
        incomingHandlesById: [UUID: WindowHandle]
    ) -> ProjectionResult {
        projectInternal(
            export: export,
            workspaceId: workspaceId,
            engine: engine,
            additionalHandlesById: incomingHandlesById
        )
    }

    private static func projectInternal(
        export: NiriStateZigKernel.RuntimeStateExport,
        workspaceId: WorkspaceDescriptor.ID,
        engine: NiriLayoutEngine,
        additionalHandlesById: [UUID: WindowHandle]
    ) -> ProjectionResult {
        struct ResolvedColumn {
            let column: NiriContainer
            let runtime: NiriStateZigKernel.RuntimeColumnState
            let windows: [NiriWindow]
            let windowStates: [NiriStateZigKernel.RuntimeWindowState]
        }

        let root = engine.ensureRoot(for: workspaceId)
        let initialColumns = root.columns
        let initialWindows = root.allWindows
        let initialWindowHandleIds = Set(initialWindows.map { $0.handle.id })

        var existingColumnsById: [NodeId: NiriContainer] = [:]
        existingColumnsById.reserveCapacity(initialColumns.count)
        for column in initialColumns {
            existingColumnsById[column.id] = column
        }

        var existingWindowsById: [NodeId: NiriWindow] = [:]
        existingWindowsById.reserveCapacity(initialWindows.count)
        for window in initialWindows {
            existingWindowsById[window.id] = window
        }

        var existingWindowsByHandleId: [UUID: NiriWindow] = [:]
        existingWindowsByHandleId.reserveCapacity(initialWindows.count)
        for window in initialWindows where existingWindowsByHandleId[window.handle.id] == nil {
            existingWindowsByHandleId[window.handle.id] = window
        }

        var handleById: [UUID: WindowHandle] = [:]
        handleById.reserveCapacity(
            engine.handleToNode.count + initialWindows.count + additionalHandlesById.count
        )
        for (handleId, handle) in additionalHandlesById {
            handleById[handleId] = handle
        }
        for handle in engine.handleToNode.keys where handleById[handle.id] == nil {
            handleById[handle.id] = handle
        }
        for window in initialWindows where handleById[window.handle.id] == nil {
            handleById[window.handle.id] = window.handle
        }

        let runtimeColumns = export.columns
        let runtimeWindows = export.windows

        var seenColumnIds = Set<NodeId>()
        seenColumnIds.reserveCapacity(runtimeColumns.count)

        var usedColumns = Set<ObjectIdentifier>()
        var usedWindows = Set<ObjectIdentifier>()
        var resolvedColumns: [ResolvedColumn] = []
        resolvedColumns.reserveCapacity(runtimeColumns.count)

        for orderedColumn in runtimeColumns {
            guard seenColumnIds.insert(orderedColumn.columnId).inserted else {
                return fail("duplicate runtime column id \(orderedColumn.columnId.uuid)")
            }

            let resolvedColumn = existingColumnsById[orderedColumn.columnId]
                ?? (engine.findNode(by: orderedColumn.columnId) as? NiriContainer)
                ?? NiriContainer(id: orderedColumn.columnId)

            let columnObjectId = ObjectIdentifier(resolvedColumn)
            guard !usedColumns.contains(columnObjectId) else {
                return fail("duplicate resolved column for id \(orderedColumn.columnId.uuid)")
            }
            usedColumns.insert(columnObjectId)

            let start = orderedColumn.windowStart
            let end = start + orderedColumn.windowCount
            guard start >= 0, end >= start, end <= runtimeWindows.count else {
                return fail("invalid runtime column window range start=\(start) count=\(orderedColumn.windowCount)")
            }

            var columnWindowStates: [NiriStateZigKernel.RuntimeWindowState] = []
            columnWindowStates.reserveCapacity(orderedColumn.windowCount)
            var resolvedWindows: [NiriWindow] = []
            resolvedWindows.reserveCapacity(orderedColumn.windowCount)

            for idx in start ..< end {
                let runtimeWindow = runtimeWindows[idx]
                if runtimeWindow.columnId != orderedColumn.columnId {
                    return fail("runtime window \(runtimeWindow.windowId.uuid) has mismatched column id")
                }

                let resolvedWindow: NiriWindow
                if let nodeById = existingWindowsById[runtimeWindow.windowId] {
                    resolvedWindow = nodeById
                } else if let globalNodeById = engine.findNode(by: runtimeWindow.windowId) as? NiriWindow {
                    resolvedWindow = globalNodeById
                } else if let nodeByHandle = existingWindowsByHandleId[runtimeWindow.windowId.uuid] {
                    resolvedWindow = nodeByHandle
                } else if let handle = handleById[runtimeWindow.windowId.uuid] {
                    resolvedWindow = NiriWindow(handle: handle, id: runtimeWindow.windowId)
                } else {
                    return fail("missing window handle for runtime window id \(runtimeWindow.windowId.uuid)")
                }

                let windowObjectId = ObjectIdentifier(resolvedWindow)
                guard !usedWindows.contains(windowObjectId) else {
                    return fail("duplicate resolved window object for runtime window id \(runtimeWindow.windowId.uuid)")
                }
                usedWindows.insert(windowObjectId)
                columnWindowStates.append(runtimeWindow)
                resolvedWindows.append(resolvedWindow)
            }

            resolvedColumns.append(
                ResolvedColumn(
                    column: resolvedColumn,
                    runtime: orderedColumn,
                    windows: resolvedWindows,
                    windowStates: columnWindowStates
                )
            )
        }

        for (targetColumnIndex, resolvedColumn) in resolvedColumns.enumerated() {
            let column = resolvedColumn.column
            root.insertChild(column, at: targetColumnIndex)

            guard let runtimeWidth = NiriStateZigKernel.decodeWidth(
                kind: resolvedColumn.runtime.widthKind,
                value: resolvedColumn.runtime.sizeValue
            ) else {
                return fail("invalid runtime width kind for column id \(resolvedColumn.runtime.columnId.uuid)")
            }

            let runtimeSavedWidth: ProportionalSize?
            if resolvedColumn.runtime.hasSavedWidth {
                guard let decoded = NiriStateZigKernel.decodeWidth(
                    kind: resolvedColumn.runtime.savedWidthKind,
                    value: resolvedColumn.runtime.savedWidthValue
                ) else {
                    return fail("invalid runtime saved width kind for column id \(resolvedColumn.runtime.columnId.uuid)")
                }
                runtimeSavedWidth = decoded
            } else {
                runtimeSavedWidth = nil
            }

            let didWidthChange = column.width != runtimeWidth ||
                column.isFullWidth != resolvedColumn.runtime.isFullWidth ||
                column.savedWidth != runtimeSavedWidth

            column.width = runtimeWidth
            column.isFullWidth = resolvedColumn.runtime.isFullWidth
            column.savedWidth = runtimeSavedWidth
            column.displayMode = resolvedColumn.runtime.isTabbed ? .tabbed : .normal
            if didWidthChange {
                column.cachedWidth = 0
                column.cachedHeight = 0
            }

            for (targetWindowIndex, window) in resolvedColumn.windows.enumerated() {
                column.insertChild(window, at: targetWindowIndex)
                let runtimeWindow = resolvedColumn.windowStates[targetWindowIndex]
                guard let runtimeHeight = NiriStateZigKernel.decodeHeight(
                    kind: runtimeWindow.heightKind,
                    value: runtimeWindow.heightValue
                ) else {
                    return fail("invalid runtime height kind for window id \(runtimeWindow.windowId.uuid)")
                }
                window.height = runtimeHeight
            }

            if resolvedColumn.windows.isEmpty {
                column.setActiveTileIdx(0)
            } else {
                column.setActiveTileIdx(resolvedColumn.runtime.activeTileIdx)
            }

            engine.updateTabbedColumnVisibility(column: column)
        }

        let activeColumnObjects = Set(resolvedColumns.map { ObjectIdentifier($0.column) })
        for staleColumn in initialColumns where !activeColumnObjects.contains(ObjectIdentifier(staleColumn)) {
            staleColumn.remove()
        }

        let activeWindowObjects = Set(resolvedColumns.flatMap { $0.windows }.map(ObjectIdentifier.init))
        for staleWindow in initialWindows where !activeWindowObjects.contains(ObjectIdentifier(staleWindow)) {
            engine.closingHandles.remove(staleWindow.handle)
            staleWindow.remove()
        }

        let activeHandleIds = Set(root.allWindows.map { $0.handle.id })
        for (handle, node) in engine.handleToNode {
            if activeHandleIds.contains(handle.id) {
                continue
            }
            if node.findRoot()?.workspaceId == workspaceId ||
                (node.findRoot() == nil && initialWindowHandleIds.contains(handle.id))
            {
                engine.handleToNode.removeValue(forKey: handle)
            }
        }
        for window in root.allWindows {
            engine.handleToNode[window.handle] = window
        }

        return ProjectionResult(applied: true, failureReason: nil)
    }

    private static func fail(_ reason: String) -> ProjectionResult {
        ProjectionResult(applied: false, failureReason: reason)
    }
}
