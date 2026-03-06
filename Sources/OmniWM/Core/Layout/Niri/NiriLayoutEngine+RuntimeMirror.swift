import Foundation

extension NiriLayoutEngine {
    enum RuntimeMirrorError: Error, CustomStringConvertible {
        case queryFailed(workspaceId: WorkspaceDescriptor.ID, reason: String)
        case missingWindowHandle(workspaceId: WorkspaceDescriptor.ID, windowId: NodeId)

        var description: String {
            switch self {
            case let .queryFailed(workspaceId, reason):
                return "runtime mirror query failed workspace=\(workspaceId): \(reason)"
            case let .missingWindowHandle(workspaceId, windowId):
                return "runtime mirror missing window handle workspace=\(workspaceId) windowId=\(windowId.uuid)"
            }
        }
    }

    @discardableResult
    func syncRuntimeWorkspaceMirror(
        workspaceId: WorkspaceDescriptor.ID,
        ensureWorkspaceRoot: Bool = true,
        additionalHandlesByWindowId: [NodeId: WindowHandle] = [:]
    ) -> Result<NiriRuntimeWorkspaceView, RuntimeMirrorError> {
        let runtimeStore = runtimeStore(
            for: workspaceId,
            ensureWorkspaceRoot: ensureWorkspaceRoot
        )

        let runtimeView: NiriRuntimeWorkspaceView
        switch runtimeStore.queryView(additionalHandlesByWindowId: additionalHandlesByWindowId) {
        case let .success(view):
            runtimeView = view
        case let .failure(error):
            return .failure(
                .queryFailed(
                    workspaceId: workspaceId,
                    reason: error.description
                )
            )
        }

        switch applyRuntimeWorkspaceView(
            runtimeView,
            additionalHandlesByWindowId: additionalHandlesByWindowId
        ) {
        case .success:
            return .success(runtimeView)
        case let .failure(error):
            return .failure(error)
        }
    }

    private func applyRuntimeWorkspaceView(
        _ view: NiriRuntimeWorkspaceView,
        additionalHandlesByWindowId: [NodeId: WindowHandle]
    ) -> Result<Void, RuntimeMirrorError> {
        let workspaceId = view.workspaceId
        let root = ensureRoot(for: workspaceId)
        let previousColumns = root.columns
        let previousWindows = root.allWindows

        var existingColumnsById: [NodeId: NiriContainer] = [:]
        existingColumnsById.reserveCapacity(previousColumns.count)
        for column in previousColumns {
            existingColumnsById[column.id] = column
        }

        var existingWindowsById: [NodeId: NiriWindow] = [:]
        existingWindowsById.reserveCapacity(previousWindows.count)
        for window in previousWindows {
            existingWindowsById[window.id] = window
        }

        var handleByWindowId: [NodeId: WindowHandle] = [:]
        handleByWindowId.reserveCapacity(handleToNode.count + additionalHandlesByWindowId.count)
        for (handle, node) in handleToNode {
            handleByWindowId[node.id] = handle
        }
        for workspaceRoot in roots.values {
            for window in workspaceRoot.allWindows where handleByWindowId[window.id] == nil {
                handleByWindowId[window.id] = window.handle
            }
        }
        for (windowId, handle) in additionalHandlesByWindowId {
            handleByWindowId[windowId] = handle
        }

        for runtimeWindow in view.windows where handleByWindowId[runtimeWindow.windowId] == nil {
            return .failure(
                .missingWindowHandle(
                    workspaceId: workspaceId,
                    windowId: runtimeWindow.windowId
                )
            )
        }

        for column in previousColumns {
            column.detach()
        }

        var seenWindowIds = Set<NodeId>()
        seenWindowIds.reserveCapacity(view.windows.count)

        for columnView in view.columns {
            let column = existingColumnsById[columnView.columnId] ?? NiriContainer(id: columnView.columnId)

            column.displayMode = columnView.isTabbed ? .tabbed : .normal
            if let resolvedWidth = columnView.width {
                column.width = resolvedWidth
            } else if columnView.widthKind == NiriStateZigKernel.sizeKindFixed {
                column.width = .fixed(CGFloat(columnView.widthValue))
            } else {
                column.width = .proportion(CGFloat(columnView.widthValue))
            }
            column.isFullWidth = columnView.isFullWidth
            column.savedWidth = columnView.savedWidth
            column.presetWidthIdx = nil
            column.cachedWidth = 0

            root.appendChild(column)

            for windowId in columnView.windowIds {
                guard let windowView = view.window(for: windowId) else { continue }
                let handle = handleByWindowId[windowId]!

                if let mappedWindow = handleToNode[handle],
                   mappedWindow.id != windowId
                {
                    mappedWindow.remove()
                    handleToNode.removeValue(forKey: handle)
                }

                let window = existingWindowsById[windowId]
                    ?? handleToNode[handle]
                    ?? NiriWindow(handle: handle, id: windowId)
                window.height = windowView.height ?? .auto(
                    weight: max(0.1, CGFloat(windowView.sizeValue))
                )

                column.appendChild(window)
                handleToNode[handle] = window
                seenWindowIds.insert(windowId)
            }

            column.setActiveTileIdx(columnView.activeTileIndex)
            updateTabbedColumnVisibility(column: column)
        }

        for previousWindow in previousWindows where !seenWindowIds.contains(previousWindow.id) {
            let handle = previousWindow.handle
            closingHandles.remove(handle)
            if let mappedWindow = handleToNode[handle],
               mappedWindow.id == previousWindow.id,
               mappedWindow.findRoot()?.workspaceId != workspaceId
            {
                continue
            }
            if let mappedWindow = handleToNode[handle],
               mappedWindow.id == previousWindow.id
            {
                handleToNode.removeValue(forKey: handle)
            }
        }

        return .success(())
    }

    func navigationRefreshColumnIds(
        sourceColumnId: NodeId?,
        targetColumnId: NodeId?
    ) -> [NodeId] {
        var refreshColumnIds: [NodeId] = []
        if let sourceColumnId {
            refreshColumnIds.append(sourceColumnId)
        }
        if let targetColumnId, !refreshColumnIds.contains(targetColumnId) {
            refreshColumnIds.append(targetColumnId)
        }
        return refreshColumnIds
    }
}
