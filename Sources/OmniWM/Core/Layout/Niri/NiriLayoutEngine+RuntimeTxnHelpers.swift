import Foundation

extension NiriLayoutEngine {
    func markRuntimeSeeded(for workspaceId: WorkspaceDescriptor.ID) {
        runtimeSeededWorkspaces.insert(workspaceId)
    }

    func prepareSeededRuntimeContext(
        for workspaceId: WorkspaceDescriptor.ID,
        snapshot: @autoclosure () -> NiriStateZigKernel.Snapshot
    ) -> NiriLayoutZigKernel.LayoutContext? {
        guard let context = ensureLayoutContext(for: workspaceId) else {
            return nil
        }
        if runtimeSeededWorkspaces.contains(workspaceId) {
            return context
        }

        let resolvedSnapshot = snapshot()
        let seedRC = NiriStateZigKernel.seedRuntimeState(
            context: context,
            snapshot: resolvedSnapshot
        )
        guard seedRC == 0 else {
            return nil
        }

        markRuntimeSeeded(for: workspaceId)
        return context
    }

    @discardableResult
    func applyProjectedRuntimeExport(
        context: NiriLayoutZigKernel.LayoutContext,
        workspaceId: WorkspaceDescriptor.ID,
        delta: NiriStateZigKernel.DeltaExport? = nil,
        refreshMirrorStateFromExport: Bool = true
    ) -> NiriStateZigKernel.DeltaExport? {
        let runtimeSnapshot = NiriStateZigKernel.snapshotRuntimeState(context: context)
        guard runtimeSnapshot.rc == 0 else {
            return nil
        }

        let projection = NiriStateZigRuntimeSnapshotApplier.project(
            export: runtimeSnapshot.export,
            workspaceId: workspaceId,
            engine: self
        )
        guard projection.applied else {
            return nil
        }

        if refreshMirrorStateFromExport {
            markRuntimeSeeded(for: workspaceId)
        }

        if let delta {
            return delta
        }

        let exportedDelta = NiriStateZigKernel.exportDelta(context: context)
        return exportedDelta.rc == 0 ? exportedDelta.export : nil
    }

    @discardableResult
    func applyProjectedLifecycleRuntimeExport(
        context: NiriLayoutZigKernel.LayoutContext,
        workspaceId: WorkspaceDescriptor.ID,
        incomingHandlesById: [UUID: WindowHandle],
        delta: NiriStateZigKernel.DeltaExport? = nil,
        refreshMirrorStateFromExport: Bool = true
    ) -> NiriStateZigKernel.DeltaExport? {
        let runtimeSnapshot = NiriStateZigKernel.snapshotRuntimeState(context: context)
        guard runtimeSnapshot.rc == 0 else {
            return nil
        }

        let projection = NiriStateZigRuntimeSnapshotApplier.projectLifecycle(
            export: runtimeSnapshot.export,
            workspaceId: workspaceId,
            engine: self,
            incomingHandlesById: incomingHandlesById
        )
        guard projection.applied else {
            return nil
        }

        if refreshMirrorStateFromExport {
            markRuntimeSeeded(for: workspaceId)
        }

        if let delta {
            return delta
        }

        let exportedDelta = NiriStateZigKernel.exportDelta(context: context)
        return exportedDelta.rc == 0 ? exportedDelta.export : nil
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
