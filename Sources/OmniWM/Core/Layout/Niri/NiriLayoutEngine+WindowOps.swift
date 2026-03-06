import AppKit
import Foundation

extension NiriLayoutEngine {
    private struct WindowMutationPreparedRequest {
        let runtimeStore: NiriRuntimeWorkspaceStore
        let command: NiriRuntimeMutationCommand
    }

    private struct WindowMutationApplyOutcome {
        let applied: Bool
        let targetWindow: NiriWindow?
        let delegatedMoveColumn: (column: NiriContainer, direction: Direction)?
    }

    private func prepareWindowMutationRequest(
        op: NiriStateZigKernel.MutationOp,
        sourceWindow: NiriWindow,
        targetWindow: NiriWindow? = nil,
        direction: Direction? = nil,
        insertPosition: InsertPosition? = nil,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> WindowMutationPreparedRequest? {
        guard let runtimeView = runtimeWorkspaceView(for: workspaceId) else {
            return nil
        }

        guard runtimeView.window(for: sourceWindow.id) != nil else {
            return nil
        }
        if let targetWindow, runtimeView.window(for: targetWindow.id) == nil {
            return nil
        }

        guard let command = windowMutationCommand(
            op: op,
            sourceWindowId: sourceWindow.id,
            targetWindowId: targetWindow?.id,
            direction: direction,
            insertPosition: insertPosition
        ) else {
            return nil
        }

        return WindowMutationPreparedRequest(
            runtimeStore: runtimeStore(for: workspaceId),
            command: command
        )
    }

    private func applyRuntimeWindowMutation(
        _ prepared: WindowMutationPreparedRequest,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> WindowMutationApplyOutcome? {
        guard let applyOutcome = applyRuntimeWindowMutationCore(prepared, in: workspaceId) else {
            return nil
        }
        guard applyOutcome.applied else {
            return WindowMutationApplyOutcome(
                applied: false,
                targetWindow: nil,
                delegatedMoveColumn: nil
            )
        }

        var runtimeOutcome = WindowMutationApplyOutcome(
            applied: true,
            targetWindow: nil,
            delegatedMoveColumn: nil
        )
        if let targetWindowId = applyOutcome.targetWindowId {
            guard let resolvedTarget = runtimeWindowNode(
                for: targetWindowId,
                in: workspaceId
            ) else {
                return nil
            }
            runtimeOutcome = WindowMutationApplyOutcome(
                applied: true,
                targetWindow: resolvedTarget,
                delegatedMoveColumn: nil
            )
        }
        if let delegated = applyOutcome.delta?.delegatedMoveColumn {
            guard let resolvedColumn = runtimeColumnNode(
                for: delegated.columnId,
                in: workspaceId
            ) else {
                return nil
            }
            runtimeOutcome = WindowMutationApplyOutcome(
                applied: true,
                targetWindow: runtimeOutcome.targetWindow,
                delegatedMoveColumn: (resolvedColumn, delegated.direction)
            )
        }

        return runtimeOutcome
    }

    private func applyRuntimeWindowMutationCore(
        _ prepared: WindowMutationPreparedRequest,
        in _: WorkspaceDescriptor.ID
    ) -> NiriRuntimeMutationOutcome? {
        let runtimeOutcome: NiriRuntimeMutationOutcome
        switch prepared.runtimeStore.executeMutation(prepared.command) {
        case let .success(outcome):
            runtimeOutcome = outcome
        case .failure:
            return nil
        }

        guard runtimeOutcome.rc == 0 else {
            return nil
        }
        return runtimeOutcome
    }

    private func applyRuntimeWindowMutationAppliedOnly(
        _ prepared: WindowMutationPreparedRequest,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> Bool? {
        guard let applyOutcome = applyRuntimeWindowMutationCore(prepared, in: workspaceId) else {
            return nil
        }
        return applyOutcome.applied
    }

    private func executePreparedWindowMutation(
        _ prepared: WindowMutationPreparedRequest,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> WindowMutationApplyOutcome? {
        applyRuntimeWindowMutation(prepared, in: workspaceId)
    }

    private func windowMutationCommand(
        op: NiriStateZigKernel.MutationOp,
        sourceWindowId: NodeId,
        targetWindowId: NodeId?,
        direction: Direction?,
        insertPosition: InsertPosition?
    ) -> NiriRuntimeMutationCommand? {
        switch op {
        case .moveWindowVertical:
            guard let direction else { return nil }
            return .moveWindowVertical(sourceWindowId: sourceWindowId, direction: direction)
        case .swapWindowVertical:
            guard let direction else { return nil }
            return .swapWindowVertical(sourceWindowId: sourceWindowId, direction: direction)
        case .moveWindowHorizontal:
            guard let direction else { return nil }
            return .moveWindowHorizontal(sourceWindowId: sourceWindowId, direction: direction)
        case .swapWindowHorizontal:
            guard let direction else { return nil }
            return .swapWindowHorizontal(sourceWindowId: sourceWindowId, direction: direction)
        case .swapWindowsByMove:
            guard let targetWindowId else { return nil }
            return .swapWindowsByMove(sourceWindowId: sourceWindowId, targetWindowId: targetWindowId)
        case .insertWindowByMove:
            guard let targetWindowId, let insertPosition else { return nil }
            return .insertWindowByMove(
                sourceWindowId: sourceWindowId,
                targetWindowId: targetWindowId,
                position: insertPosition
            )
        default:
            return nil
        }
    }

    func applyWindowMutation(
        op: NiriStateZigKernel.MutationOp,
        sourceWindow: NiriWindow,
        targetWindow: NiriWindow? = nil,
        direction: Direction? = nil,
        insertPosition: InsertPosition? = nil,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> (applied: Bool, targetWindow: NiriWindow?, delegatedMoveColumn: (column: NiriContainer, direction: Direction)?)? {
        guard let prepared = prepareWindowMutationRequest(
            op: op,
            sourceWindow: sourceWindow,
            targetWindow: targetWindow,
            direction: direction,
            insertPosition: insertPosition,
            in: workspaceId
        ) else {
            return nil
        }
        guard let outcome = executePreparedWindowMutation(prepared, in: workspaceId) else {
            return nil
        }
        return (
            applied: outcome.applied,
            targetWindow: outcome.targetWindow,
            delegatedMoveColumn: outcome.delegatedMoveColumn
        )
    }

    func moveWindow(
        _ node: NiriWindow,
        direction: Direction,
        in workspaceId: WorkspaceDescriptor.ID,
        state: inout ViewportState,
        workingFrame: CGRect,
        gaps: CGFloat
    ) -> Bool {
        let latencyToken = NiriLatencyProbe.begin(.windowMove)
        defer { NiriLatencyProbe.end(latencyToken) }

        return switch direction {
        case .down, .up:
            moveWindowVertical(node, direction: direction, in: workspaceId)
        case .left, .right:
            moveWindowHorizontal(
                node,
                direction: direction,
                in: workspaceId,
                state: &state,
                workingFrame: workingFrame,
                gaps: gaps
            )
        }
    }

    func swapWindow(
        _ node: NiriWindow,
        direction: Direction,
        in workspaceId: WorkspaceDescriptor.ID,
        state: inout ViewportState,
        workingFrame: CGRect,
        gaps: CGFloat
    ) -> Bool {
        switch direction {
        case .down, .up:
            swapWindowVertical(node, direction: direction, in: workspaceId)
        case .left, .right:
            swapWindowHorizontal(
                node,
                direction: direction,
                in: workspaceId,
                state: &state,
                workingFrame: workingFrame,
                gaps: gaps
            )
        }
    }

    private func moveWindowVertical(
        _ node: NiriWindow,
        direction: Direction,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> Bool {
        guard let prepared = prepareWindowMutationRequest(
            op: .moveWindowVertical,
            sourceWindow: node,
            direction: direction,
            in: workspaceId
        ) else {
            return false
        }
        guard let applied = applyRuntimeWindowMutationAppliedOnly(prepared, in: workspaceId) else {
            return false
        }
        return applied
    }

    private func swapWindowVertical(
        _ node: NiriWindow,
        direction: Direction,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> Bool {
        guard let prepared = prepareWindowMutationRequest(
            op: .swapWindowVertical,
            sourceWindow: node,
            direction: direction,
            in: workspaceId
        ) else {
            return false
        }
        guard let applied = applyRuntimeWindowMutationAppliedOnly(prepared, in: workspaceId) else {
            return false
        }
        return applied
    }

    private func moveWindowHorizontal(
        _ node: NiriWindow,
        direction: Direction,
        in workspaceId: WorkspaceDescriptor.ID,
        state: inout ViewportState,
        workingFrame: CGRect,
        gaps: CGFloat
    ) -> Bool {
        guard let applyOutcome = applyWindowMutation(
            op: .moveWindowHorizontal,
            sourceWindow: node,
            direction: direction,
            in: workspaceId
        ) else {
            return false
        }
        guard applyOutcome.applied else {
            return false
        }

        let targetNode = applyOutcome.targetWindow ?? node
        ensureSelectionVisible(
            node: targetNode,
            in: workspaceId,
            state: &state,
            workingFrame: workingFrame,
            gaps: gaps,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn
        )

        return true
    }

    private func swapWindowHorizontal(
        _ node: NiriWindow,
        direction: Direction,
        in workspaceId: WorkspaceDescriptor.ID,
        state: inout ViewportState,
        workingFrame: CGRect,
        gaps: CGFloat
    ) -> Bool {
        guard let prepared = prepareWindowMutationRequest(
            op: .swapWindowHorizontal,
            sourceWindow: node,
            direction: direction,
            in: workspaceId
        ) else {
            return false
        }

        guard let applyOutcome = executePreparedWindowMutation(
            prepared,
            in: workspaceId
        )
        else {
            return false
        }
        guard applyOutcome.applied else {
            return false
        }

        if let delegated = applyOutcome.delegatedMoveColumn {
            return moveColumn(
                delegated.column,
                direction: delegated.direction,
                in: workspaceId,
                state: &state,
                workingFrame: workingFrame,
                gaps: gaps
            )
        }

        let targetNode = applyOutcome.targetWindow ?? node
        ensureSelectionVisible(
            node: targetNode,
            in: workspaceId,
            state: &state,
            workingFrame: workingFrame,
            gaps: gaps,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn
        )

        return true
    }
}
