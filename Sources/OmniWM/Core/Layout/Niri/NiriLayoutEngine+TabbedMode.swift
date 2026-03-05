import AppKit
import Foundation

extension NiriLayoutEngine {
    @discardableResult
    func toggleColumnTabbed(in workspaceId: WorkspaceDescriptor.ID, state: ViewportState) -> Bool {
        guard let selectedId = state.selectedNodeId,
              let selectedNode = findNode(by: selectedId),
              let column = column(of: selectedNode)
        else {
            return false
        }

        let newMode: ColumnDisplay = column.displayMode == .normal ? .tabbed : .normal
        return setColumnDisplay(newMode, for: column)
    }

    @discardableResult
    func setColumnDisplay(_ mode: ColumnDisplay, for column: NiriContainer, gaps _: CGFloat = 0) -> Bool {
        guard column.displayMode != mode else { return false }
        guard let workspaceId = column.findRoot()?.workspaceId else { return false }

        if let resize = interactiveResize,
           let resizeWindow = findNode(by: resize.windowId) as? NiriWindow,
           let resizeColumn = findColumn(containing: resizeWindow, in: resize.workspaceId),
           resizeColumn.id == column.id
        {
            clearInteractiveResize()
        }

        let runtimeStore = runtimeStore(for: workspaceId)
        switch runtimeStore.executeMutation(
            .setColumnDisplay(
                sourceColumnId: column.id,
                mode: mode
            )
        ) {
        case let .success(outcome):
            guard outcome.rc == 0 else { return false }
            return outcome.applied
        case .failure:
            return false
        }
    }

    func updateTabbedColumnVisibility(column: NiriContainer) {
        let windows = column.windowNodes
        guard !windows.isEmpty else { return }

        column.clampActiveTileIdx()

        if column.displayMode == .tabbed {
            for (idx, window) in windows.enumerated() {
                let isActive = idx == column.activeTileIdx
                window.isHiddenInTabbedMode = !isActive
            }
        } else {
            for window in windows {
                window.isHiddenInTabbedMode = false
            }
        }
    }

    @discardableResult
    func activateTab(at index: Int, in column: NiriContainer) -> Bool {
        guard column.displayMode == .tabbed else { return false }
        guard let workspaceId = column.findRoot()?.workspaceId else { return false }

        let runtimeStore = runtimeStore(for: workspaceId)
        switch runtimeStore.executeMutation(
            .setColumnActiveTile(
                sourceColumnId: column.id,
                tileIndex: index
            )
        ) {
        case let .success(outcome):
            guard outcome.rc == 0 else { return false }
            return outcome.applied
        case .failure:
            return false
        }
    }

    func activeColumn(in _: WorkspaceDescriptor.ID, state: ViewportState) -> NiriContainer? {
        guard let selectedId = state.selectedNodeId,
              let selectedNode = findNode(by: selectedId)
        else {
            return nil
        }
        return column(of: selectedNode)
    }
}
