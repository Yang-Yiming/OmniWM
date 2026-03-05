import Foundation

extension NiriLayoutEngine {
    enum RuntimeProjectionError: Error, CustomStringConvertible {
        case runtimeSnapshot(workspaceId: WorkspaceDescriptor.ID, error: NiriStateZigKernel.RuntimeExportDecodeError)
        case runtimeDeltaExport(workspaceId: WorkspaceDescriptor.ID, error: NiriStateZigKernel.RuntimeExportDecodeError)
        case projection(workspaceId: WorkspaceDescriptor.ID, error: NiriStateZigRuntimeSnapshotApplier.ProjectionError)
        case workspaceProjection(error: NiriStateZigRuntimeSnapshotApplier.WorkspaceProjectionError)
        case unknownProjection(workspaceId: WorkspaceDescriptor.ID)
        case unknownWorkspaceProjection

        var description: String {
            switch self {
            case let .runtimeSnapshot(workspaceId, error):
                return "runtime snapshot decode failed workspace=\(workspaceId): \(error.description)"
            case let .runtimeDeltaExport(workspaceId, error):
                return "runtime delta export decode failed workspace=\(workspaceId): \(error.description)"
            case let .projection(workspaceId, error):
                return "runtime projection failed workspace=\(workspaceId): \(error.description)"
            case let .workspaceProjection(error):
                return "runtime workspace projection failed: \(error.description)"
            case let .unknownProjection(workspaceId):
                return "runtime projection failed workspace=\(workspaceId): unknown error"
            case .unknownWorkspaceProjection:
                return "runtime workspace projection failed: unknown error"
            }
        }
    }

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
    ) -> Result<NiriStateZigKernel.DeltaExport?, RuntimeProjectionError> {
        let runtimeSnapshotResult = NiriStateZigKernel.snapshotRuntimeStateResult(context: context)
        let runtimeSnapshot: NiriStateZigKernel.RuntimeStateExport
        switch runtimeSnapshotResult {
        case let .success(export):
            runtimeSnapshot = export
        case let .failure(error):
            return .failure(.runtimeSnapshot(workspaceId: workspaceId, error: error))
        }

        let projection = NiriStateZigRuntimeSnapshotApplier.project(
            export: runtimeSnapshot,
            workspaceId: workspaceId,
            engine: self
        )
        guard projection.applied else {
            if let error = projection.error {
                return .failure(.projection(workspaceId: workspaceId, error: error))
            }
            return .failure(.unknownProjection(workspaceId: workspaceId))
        }

        if refreshMirrorStateFromExport {
            markRuntimeSeeded(for: workspaceId)
        }

        if let delta {
            return .success(delta)
        }

        let deltaResult = NiriStateZigKernel.exportDeltaResult(context: context)
        switch deltaResult {
        case let .success(exported):
            return .success(exported)
        case let .failure(error):
            return .failure(.runtimeDeltaExport(workspaceId: workspaceId, error: error))
        }
    }

    @discardableResult
    func applyProjectedLifecycleRuntimeExport(
        context: NiriLayoutZigKernel.LayoutContext,
        workspaceId: WorkspaceDescriptor.ID,
        incomingHandlesById: [UUID: WindowHandle],
        delta: NiriStateZigKernel.DeltaExport? = nil,
        refreshMirrorStateFromExport: Bool = true
    ) -> Result<NiriStateZigKernel.DeltaExport?, RuntimeProjectionError> {
        let runtimeSnapshotResult = NiriStateZigKernel.snapshotRuntimeStateResult(context: context)
        let runtimeSnapshot: NiriStateZigKernel.RuntimeStateExport
        switch runtimeSnapshotResult {
        case let .success(export):
            runtimeSnapshot = export
        case let .failure(error):
            return .failure(.runtimeSnapshot(workspaceId: workspaceId, error: error))
        }

        let projection = NiriStateZigRuntimeSnapshotApplier.projectLifecycle(
            export: runtimeSnapshot,
            workspaceId: workspaceId,
            engine: self,
            incomingHandlesById: incomingHandlesById
        )
        guard projection.applied else {
            if let error = projection.error {
                return .failure(.projection(workspaceId: workspaceId, error: error))
            }
            return .failure(.unknownProjection(workspaceId: workspaceId))
        }

        if refreshMirrorStateFromExport {
            markRuntimeSeeded(for: workspaceId)
        }

        if let delta {
            return .success(delta)
        }

        let deltaResult = NiriStateZigKernel.exportDeltaResult(context: context)
        switch deltaResult {
        case let .success(exported):
            return .success(exported)
        case let .failure(error):
            return .failure(.runtimeDeltaExport(workspaceId: workspaceId, error: error))
        }
    }

    @discardableResult
    func applyProjectedWorkspaceRuntimeExports(
        sourceContext: NiriLayoutZigKernel.LayoutContext,
        sourceWorkspaceId: WorkspaceDescriptor.ID,
        targetContext: NiriLayoutZigKernel.LayoutContext,
        targetWorkspaceId: WorkspaceDescriptor.ID,
        sourceDelta: NiriStateZigKernel.DeltaExport? = nil,
        targetDelta: NiriStateZigKernel.DeltaExport? = nil,
        refreshMirrorStateFromExport: Bool = true
    ) -> Result<(
        sourceDelta: NiriStateZigKernel.DeltaExport?,
        targetDelta: NiriStateZigKernel.DeltaExport?
    ), RuntimeProjectionError> {
        let sourceSnapshot: NiriStateZigKernel.RuntimeStateExport
        switch NiriStateZigKernel.snapshotRuntimeStateResult(context: sourceContext) {
        case let .success(export):
            sourceSnapshot = export
        case let .failure(error):
            return .failure(.runtimeSnapshot(workspaceId: sourceWorkspaceId, error: error))
        }

        let targetSnapshot: NiriStateZigKernel.RuntimeStateExport
        switch NiriStateZigKernel.snapshotRuntimeStateResult(context: targetContext) {
        case let .success(export):
            targetSnapshot = export
        case let .failure(error):
            return .failure(.runtimeSnapshot(workspaceId: targetWorkspaceId, error: error))
        }

        let workspaceProjection = NiriStateZigRuntimeSnapshotApplier.projectWorkspaceSet(
            sourceExport: sourceSnapshot,
            sourceWorkspaceId: sourceWorkspaceId,
            targetExport: targetSnapshot,
            targetWorkspaceId: targetWorkspaceId,
            engine: self
        )
        guard workspaceProjection.applied else {
            if let error = workspaceProjection.error {
                return .failure(.workspaceProjection(error: error))
            }
            return .failure(.unknownWorkspaceProjection)
        }

        if refreshMirrorStateFromExport {
            markRuntimeSeeded(for: sourceWorkspaceId)
            markRuntimeSeeded(for: targetWorkspaceId)
        }

        let resolvedSourceDelta: NiriStateZigKernel.DeltaExport?
        if let sourceDelta {
            resolvedSourceDelta = sourceDelta
        } else {
            switch NiriStateZigKernel.exportDeltaResult(context: sourceContext) {
            case let .success(exported):
                resolvedSourceDelta = exported
            case let .failure(error):
                return .failure(.runtimeDeltaExport(workspaceId: sourceWorkspaceId, error: error))
            }
        }

        let resolvedTargetDelta: NiriStateZigKernel.DeltaExport?
        if let targetDelta {
            resolvedTargetDelta = targetDelta
        } else {
            switch NiriStateZigKernel.exportDeltaResult(context: targetContext) {
            case let .success(exported):
                resolvedTargetDelta = exported
            case let .failure(error):
                return .failure(.runtimeDeltaExport(workspaceId: targetWorkspaceId, error: error))
            }
        }

        return .success((sourceDelta: resolvedSourceDelta, targetDelta: resolvedTargetDelta))
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
