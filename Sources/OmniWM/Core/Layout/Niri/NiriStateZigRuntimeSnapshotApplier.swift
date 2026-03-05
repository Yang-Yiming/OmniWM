import Foundation

enum NiriStateZigRuntimeSnapshotApplier {
    enum ProjectionError: Error, Equatable, CustomStringConvertible {
        case duplicateRuntimeColumnId(NodeId)
        case duplicateResolvedColumn(NodeId)
        case invalidRuntimeColumnWindowRange(columnId: NodeId, start: Int, count: Int)
        case mismatchedRuntimeWindowColumn(windowId: NodeId, expectedColumnId: NodeId, actualColumnId: NodeId)
        case missingWindowHandle(NodeId)
        case duplicateResolvedWindow(NodeId)
        case invalidRuntimeColumnWidth(columnId: NodeId, kind: UInt8, value: Double)
        case invalidRuntimeSavedColumnWidth(columnId: NodeId, kind: UInt8, value: Double)
        case invalidRuntimeWindowHeight(windowId: NodeId, kind: UInt8, value: Double)

        var description: String {
            switch self {
            case let .duplicateRuntimeColumnId(columnId):
                return "duplicate runtime column id \(columnId.uuid)"
            case let .duplicateResolvedColumn(columnId):
                return "duplicate resolved column for id \(columnId.uuid)"
            case let .invalidRuntimeColumnWindowRange(columnId, start, count):
                return "invalid runtime column window range column=\(columnId.uuid) start=\(start) count=\(count)"
            case let .mismatchedRuntimeWindowColumn(windowId, expectedColumnId, actualColumnId):
                return "runtime window \(windowId.uuid) column mismatch expected=\(expectedColumnId.uuid) actual=\(actualColumnId.uuid)"
            case let .missingWindowHandle(windowId):
                return "missing window handle for runtime window id \(windowId.uuid)"
            case let .duplicateResolvedWindow(windowId):
                return "duplicate resolved window object for runtime window id \(windowId.uuid)"
            case let .invalidRuntimeColumnWidth(columnId, kind, value):
                return "invalid runtime width kind for column id \(columnId.uuid) kind=\(kind) value=\(value)"
            case let .invalidRuntimeSavedColumnWidth(columnId, kind, value):
                return "invalid runtime saved width kind for column id \(columnId.uuid) kind=\(kind) value=\(value)"
            case let .invalidRuntimeWindowHeight(windowId, kind, value):
                return "invalid runtime height kind for window id \(windowId.uuid) kind=\(kind) value=\(value)"
            }
        }
    }

    enum WorkspaceProjectionError: Error, Equatable, CustomStringConvertible {
        case source(ProjectionError)
        case target(ProjectionError)

        var description: String {
            switch self {
            case let .source(error):
                return "source projection failed: \(error.description)"
            case let .target(error):
                return "target projection failed: \(error.description)"
            }
        }
    }

    struct ProjectionResult {
        let applied: Bool
        let error: ProjectionError?

        var failureReason: String? {
            error?.description
        }
    }

    struct WorkspaceProjectionResult {
        let applied: Bool
        let error: WorkspaceProjectionError?

        var failureReason: String? {
            error?.description
        }
    }

    private struct PreparedWindow {
        let window: NiriWindow
        let runtime: NiriStateZigKernel.RuntimeWindowState
        let resolvedHeight: WeightedSize
    }

    private struct PreparedColumn {
        let column: NiriContainer
        let runtime: NiriStateZigKernel.RuntimeColumnState
        let windows: [PreparedWindow]
        let resolvedWidth: ProportionalSize
        let resolvedSavedWidth: ProportionalSize?
    }

    private struct ProjectionPlan {
        let workspaceId: WorkspaceDescriptor.ID
        let root: NiriRoot
        let initialColumns: [NiriContainer]
        let initialWindows: [NiriWindow]
        let initialWindowHandleIds: Set<UUID>
        let columns: [PreparedColumn]
    }

    static func project(
        export: NiriStateZigKernel.RuntimeStateExport,
        workspaceId: WorkspaceDescriptor.ID,
        engine: NiriLayoutEngine
    ) -> ProjectionResult {
        switch prepareProjection(
            export: export,
            workspaceId: workspaceId,
            engine: engine,
            additionalHandlesById: [:]
        ) {
        case let .failure(error):
            return ProjectionResult(applied: false, error: error)
        case let .success(plan):
            commitProjection(plan, engine: engine)
            return ProjectionResult(applied: true, error: nil)
        }
    }

    static func projectLifecycle(
        export: NiriStateZigKernel.RuntimeStateExport,
        workspaceId: WorkspaceDescriptor.ID,
        engine: NiriLayoutEngine,
        incomingHandlesById: [UUID: WindowHandle]
    ) -> ProjectionResult {
        switch prepareProjection(
            export: export,
            workspaceId: workspaceId,
            engine: engine,
            additionalHandlesById: incomingHandlesById
        ) {
        case let .failure(error):
            return ProjectionResult(applied: false, error: error)
        case let .success(plan):
            commitProjection(plan, engine: engine)
            return ProjectionResult(applied: true, error: nil)
        }
    }

    static func projectWorkspaceSet(
        sourceExport: NiriStateZigKernel.RuntimeStateExport,
        sourceWorkspaceId: WorkspaceDescriptor.ID,
        targetExport: NiriStateZigKernel.RuntimeStateExport,
        targetWorkspaceId: WorkspaceDescriptor.ID,
        engine: NiriLayoutEngine
    ) -> WorkspaceProjectionResult {
        let sourcePlan: ProjectionPlan
        switch prepareProjection(
            export: sourceExport,
            workspaceId: sourceWorkspaceId,
            engine: engine,
            additionalHandlesById: [:]
        ) {
        case let .failure(error):
            return WorkspaceProjectionResult(applied: false, error: .source(error))
        case let .success(plan):
            sourcePlan = plan
        }

        let targetPlan: ProjectionPlan
        switch prepareProjection(
            export: targetExport,
            workspaceId: targetWorkspaceId,
            engine: engine,
            additionalHandlesById: [:]
        ) {
        case let .failure(error):
            return WorkspaceProjectionResult(applied: false, error: .target(error))
        case let .success(plan):
            targetPlan = plan
        }

        // Both projections are fully validated before any Swift graph mutation occurs.
        commitProjection(targetPlan, engine: engine)
        commitProjection(sourcePlan, engine: engine)
        return WorkspaceProjectionResult(applied: true, error: nil)
    }

    private static func prepareProjection(
        export: NiriStateZigKernel.RuntimeStateExport,
        workspaceId: WorkspaceDescriptor.ID,
        engine: NiriLayoutEngine,
        additionalHandlesById: [UUID: WindowHandle]
    ) -> Result<ProjectionPlan, ProjectionError> {
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
        var preparedColumns: [PreparedColumn] = []
        preparedColumns.reserveCapacity(runtimeColumns.count)

        for runtimeColumn in runtimeColumns {
            guard seenColumnIds.insert(runtimeColumn.columnId).inserted else {
                return .failure(.duplicateRuntimeColumnId(runtimeColumn.columnId))
            }

            let resolvedColumn = existingColumnsById[runtimeColumn.columnId]
                ?? (engine.findNode(by: runtimeColumn.columnId) as? NiriContainer)
                ?? NiriContainer(id: runtimeColumn.columnId)

            let columnObjectId = ObjectIdentifier(resolvedColumn)
            guard !usedColumns.contains(columnObjectId) else {
                return .failure(.duplicateResolvedColumn(runtimeColumn.columnId))
            }
            usedColumns.insert(columnObjectId)

            let start = runtimeColumn.windowStart
            let count = runtimeColumn.windowCount
            guard start >= 0,
                  count >= 0,
                  start <= runtimeWindows.count,
                  count <= runtimeWindows.count - start
            else {
                return .failure(
                    .invalidRuntimeColumnWindowRange(
                        columnId: runtimeColumn.columnId,
                        start: start,
                        count: count
                    )
                )
            }
            let end = start + count

            guard let resolvedWidth = NiriStateZigKernel.decodeWidth(
                kind: runtimeColumn.widthKind,
                value: runtimeColumn.sizeValue
            ) else {
                return .failure(
                    .invalidRuntimeColumnWidth(
                        columnId: runtimeColumn.columnId,
                        kind: runtimeColumn.widthKind,
                        value: runtimeColumn.sizeValue
                    )
                )
            }

            let resolvedSavedWidth: ProportionalSize?
            if runtimeColumn.hasSavedWidth {
                guard let decodedSavedWidth = NiriStateZigKernel.decodeWidth(
                    kind: runtimeColumn.savedWidthKind,
                    value: runtimeColumn.savedWidthValue
                ) else {
                    return .failure(
                        .invalidRuntimeSavedColumnWidth(
                            columnId: runtimeColumn.columnId,
                            kind: runtimeColumn.savedWidthKind,
                            value: runtimeColumn.savedWidthValue
                        )
                    )
                }
                resolvedSavedWidth = decodedSavedWidth
            } else {
                resolvedSavedWidth = nil
            }

            var preparedWindows: [PreparedWindow] = []
            preparedWindows.reserveCapacity(count)

            for idx in start ..< end {
                let runtimeWindow = runtimeWindows[idx]
                if runtimeWindow.columnId != runtimeColumn.columnId {
                    return .failure(
                        .mismatchedRuntimeWindowColumn(
                            windowId: runtimeWindow.windowId,
                            expectedColumnId: runtimeColumn.columnId,
                            actualColumnId: runtimeWindow.columnId
                        )
                    )
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
                    return .failure(.missingWindowHandle(runtimeWindow.windowId))
                }

                let windowObjectId = ObjectIdentifier(resolvedWindow)
                guard !usedWindows.contains(windowObjectId) else {
                    return .failure(.duplicateResolvedWindow(runtimeWindow.windowId))
                }
                usedWindows.insert(windowObjectId)

                guard let resolvedHeight = NiriStateZigKernel.decodeHeight(
                    kind: runtimeWindow.heightKind,
                    value: runtimeWindow.heightValue
                ) else {
                    return .failure(
                        .invalidRuntimeWindowHeight(
                            windowId: runtimeWindow.windowId,
                            kind: runtimeWindow.heightKind,
                            value: runtimeWindow.heightValue
                        )
                    )
                }

                preparedWindows.append(
                    PreparedWindow(
                        window: resolvedWindow,
                        runtime: runtimeWindow,
                        resolvedHeight: resolvedHeight
                    )
                )
            }

            preparedColumns.append(
                PreparedColumn(
                    column: resolvedColumn,
                    runtime: runtimeColumn,
                    windows: preparedWindows,
                    resolvedWidth: resolvedWidth,
                    resolvedSavedWidth: resolvedSavedWidth
                )
            )
        }

        return .success(
            ProjectionPlan(
                workspaceId: workspaceId,
                root: root,
                initialColumns: initialColumns,
                initialWindows: initialWindows,
                initialWindowHandleIds: initialWindowHandleIds,
                columns: preparedColumns
            )
        )
    }

    private static func commitProjection(
        _ plan: ProjectionPlan,
        engine: NiriLayoutEngine
    ) {
        let root = plan.root

        for (targetColumnIndex, resolvedColumn) in plan.columns.enumerated() {
            let column = resolvedColumn.column
            root.insertChild(column, at: targetColumnIndex)

            let didWidthChange = column.width != resolvedColumn.resolvedWidth ||
                column.isFullWidth != resolvedColumn.runtime.isFullWidth ||
                column.savedWidth != resolvedColumn.resolvedSavedWidth

            column.width = resolvedColumn.resolvedWidth
            column.isFullWidth = resolvedColumn.runtime.isFullWidth
            column.savedWidth = resolvedColumn.resolvedSavedWidth
            column.displayMode = resolvedColumn.runtime.isTabbed ? .tabbed : .normal
            if didWidthChange {
                column.cachedWidth = 0
                column.cachedHeight = 0
            }

            for (targetWindowIndex, preparedWindow) in resolvedColumn.windows.enumerated() {
                column.insertChild(preparedWindow.window, at: targetWindowIndex)
                preparedWindow.window.height = preparedWindow.resolvedHeight
            }

            if resolvedColumn.windows.isEmpty {
                column.setActiveTileIdx(0)
            } else {
                column.setActiveTileIdx(resolvedColumn.runtime.activeTileIdx)
            }

            engine.updateTabbedColumnVisibility(column: column)
        }

        let activeColumnObjects = Set(plan.columns.map { ObjectIdentifier($0.column) })
        for staleColumn in plan.initialColumns where !activeColumnObjects.contains(ObjectIdentifier(staleColumn)) {
            staleColumn.remove()
        }

        let activeWindowObjects = Set(plan.columns.flatMap { $0.windows }.map { ObjectIdentifier($0.window) })
        for staleWindow in plan.initialWindows where !activeWindowObjects.contains(ObjectIdentifier(staleWindow)) {
            engine.closingHandles.remove(staleWindow.handle)
            staleWindow.remove()
        }

        let activeHandleIds = Set(root.allWindows.map { $0.handle.id })
        for (handle, node) in engine.handleToNode {
            if activeHandleIds.contains(handle.id) {
                continue
            }
            if node.findRoot()?.workspaceId == plan.workspaceId ||
                (node.findRoot() == nil && plan.initialWindowHandleIds.contains(handle.id))
            {
                engine.handleToNode.removeValue(forKey: handle)
            }
        }
        for window in root.allWindows {
            engine.handleToNode[window.handle] = window
        }
    }
}
