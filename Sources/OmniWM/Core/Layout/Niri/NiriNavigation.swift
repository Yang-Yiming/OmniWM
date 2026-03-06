import AppKit
import CZigLayout
import Foundation

extension NiriLayoutEngine {
    private func resolveNavigationTargetNode(
        workspaceId: WorkspaceDescriptor.ID,
        op: NiriStateZigKernel.NavigationOp,
        currentSelection: NiriNode,
        direction: Direction? = nil,
        orientation: Monitor.Orientation = .horizontal,
        step: Int = 0,
        targetRowIndex: Int = -1,
        focusColumnIndex: Int = -1,
        focusWindowIndex: Int = -1,
        allowMissingSelection: Bool = false
    ) -> NiriNode? {
        let selectionAnchor = runtimeSelectionAnchor(
            selectedNodeId: currentSelection.id,
            workspaceId: workspaceId
        )
        if selectionAnchor == nil, !allowMissingSelection {
            return nil
        }

        let command: NiriRuntimeNavigationCommand?
        switch op {
        case .moveByColumns:
            if let selectionAnchor {
                command = .moveByColumns(
                    selection: selectionAnchor,
                    step: step,
                    targetRowIndex: targetRowIndex >= 0 ? targetRowIndex : nil
                )
            } else {
                command = nil
            }
        case .moveVertical:
            if let selectionAnchor, let direction {
                command = .moveVertical(
                    selection: selectionAnchor,
                    direction: direction,
                    orientation: orientation
                )
            } else {
                command = nil
            }
        case .focusTarget:
            if let selectionAnchor, let direction {
                command = .focusTarget(
                    selection: selectionAnchor,
                    direction: direction,
                    orientation: orientation
                )
            } else {
                command = nil
            }
        case .focusDownOrLeft:
            if let selectionAnchor {
                command = .focusDownOrLeft(selection: selectionAnchor)
            } else {
                command = nil
            }
        case .focusUpOrRight:
            if let selectionAnchor {
                command = .focusUpOrRight(selection: selectionAnchor)
            } else {
                command = nil
            }
        case .focusColumnFirst:
            command = .focusColumnFirst(selection: selectionAnchor)
        case .focusColumnLast:
            command = .focusColumnLast(selection: selectionAnchor)
        case .focusColumnIndex:
            guard focusColumnIndex >= 0 else { return nil }
            command = .focusColumnIndex(selection: selectionAnchor, columnIndex: focusColumnIndex)
        case .focusWindowIndex:
            if let selectionAnchor, focusWindowIndex >= 0 {
                command = .focusWindowIndex(selection: selectionAnchor, windowIndex: focusWindowIndex)
            } else {
                command = nil
            }
        case .focusWindowTop:
            if let selectionAnchor {
                command = .focusWindowTop(selection: selectionAnchor)
            } else {
                command = nil
            }
        case .focusWindowBottom:
            if let selectionAnchor {
                command = .focusWindowBottom(selection: selectionAnchor)
            } else {
                command = nil
            }
        }
        guard let command else {
            return nil
        }

        let runtimeStore = runtimeStore(for: workspaceId)
        let outcome: NiriRuntimeNavigationOutcome
        switch runtimeStore.executeNavigation(command) {
        case let .success(resolved):
            outcome = resolved
        case .failure:
            return nil
        }
        guard outcome.rc == OMNI_OK else {
            return nil
        }

        guard let targetWindowId = outcome.targetWindowId else {
            return nil
        }
        return runtimeWindowNode(
            for: targetWindowId,
            in: workspaceId
        )
    }

    private func resolveWorkspaceNavigationTargetNode(
        workspaceId: WorkspaceDescriptor.ID,
        op: NiriStateZigKernel.NavigationOp,
        currentSelection: NiriNode,
        direction: Direction? = nil,
        orientation: Monitor.Orientation = .horizontal,
        step: Int = 0,
        targetRowIndex: Int = -1,
        focusColumnIndex: Int = -1,
        focusWindowIndex: Int = -1,
        allowMissingSelection: Bool = false
    ) -> NiriNode? {
        guard let runtimeView = runtimeWorkspaceView(for: workspaceId),
              !runtimeView.columns.isEmpty
        else {
            return nil
        }

        return resolveNavigationTargetNode(
            workspaceId: workspaceId,
            op: op,
            currentSelection: currentSelection,
            direction: direction,
            orientation: orientation,
            step: step,
            targetRowIndex: targetRowIndex,
            focusColumnIndex: focusColumnIndex,
            focusWindowIndex: focusWindowIndex,
            allowMissingSelection: allowMissingSelection
        )
    }

    func moveSelectionByColumns(
        steps: Int,
        currentSelection: NiriNode,
        in workspaceId: WorkspaceDescriptor.ID,
        targetRowIndex: Int? = nil
    ) -> NiriNode? {
        let latencyToken = NiriLatencyProbe.begin(.navigationStep)
        defer { NiriLatencyProbe.end(latencyToken) }

        guard steps != 0 else { return currentSelection }

        return resolveWorkspaceNavigationTargetNode(
            workspaceId: workspaceId,
            op: .moveByColumns,
            currentSelection: currentSelection,
            step: steps,
            targetRowIndex: targetRowIndex ?? -1
        )
    }

    func moveSelectionHorizontal(
        direction: Direction,
        currentSelection: NiriNode,
        in workspaceId: WorkspaceDescriptor.ID,
        state: inout ViewportState,
        workingFrame: CGRect,
        gaps: CGFloat,
        targetRowIndex: Int? = nil
    ) -> NiriNode? {
        moveSelectionCrossContainer(
            direction: direction,
            currentSelection: currentSelection,
            in: workspaceId,
            state: &state,
            workingFrame: workingFrame,
            gaps: gaps,
            orientation: .horizontal,
            targetSiblingIndex: targetRowIndex
        )
    }

    private func moveSelectionCrossContainer(
        direction: Direction,
        currentSelection: NiriNode,
        in workspaceId: WorkspaceDescriptor.ID,
        state: inout ViewportState,
        workingFrame: CGRect,
        gaps: CGFloat,
        orientation: Monitor.Orientation,
        targetSiblingIndex: Int? = nil
    ) -> NiriNode? {
        guard let step = direction.primaryStep(for: orientation) else { return nil }

        guard let newSelection = moveSelectionByColumns(
            steps: step,
            currentSelection: currentSelection,
            in: workspaceId,
            targetRowIndex: targetSiblingIndex
        ) else {
            return nil
        }

        state.activatePrevColumnOnRemoval = nil

        ensureSelectionVisible(
            node: newSelection,
            in: workspaceId,
            state: &state,
            workingFrame: workingFrame,
            gaps: gaps,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn,
            orientation: orientation
        )

        return newSelection
    }

    func moveSelectionVertical(
        direction: Direction,
        currentSelection: NiriNode,
        in workspaceId: WorkspaceDescriptor.ID? = nil
    ) -> NiriNode? {
        moveSelectionWithinContainer(
            direction: direction,
            currentSelection: currentSelection,
            orientation: .horizontal,
            workspaceId: workspaceId
        )
    }

    private func moveSelectionWithinContainer(
        direction: Direction,
        currentSelection: NiriNode,
        orientation: Monitor.Orientation,
        workspaceId: WorkspaceDescriptor.ID? = nil
    ) -> NiriNode? {
        guard let step = direction.secondaryStep(for: orientation) else { return nil }

        guard column(of: currentSelection) != nil else {
            return step > 0 ? currentSelection.nextSibling() : currentSelection.prevSibling()
        }

        guard let resolvedWorkspaceId = workspaceId ?? currentSelection.findRoot()?.workspaceId else {
            return step > 0 ? currentSelection.nextSibling() : currentSelection.prevSibling()
        }

        return resolveWorkspaceNavigationTargetNode(
            workspaceId: resolvedWorkspaceId,
            op: .moveVertical,
            currentSelection: currentSelection,
            direction: direction,
            orientation: orientation
        )
    }

    func ensureSelectionVisible(
        node: NiriNode,
        in workspaceId: WorkspaceDescriptor.ID,
        state: inout ViewportState,
        workingFrame: CGRect,
        gaps: CGFloat,
        alwaysCenterSingleColumn: Bool,
        orientation: Monitor.Orientation = .horizontal,
        animationConfig: SpringConfig? = nil,
        fromContainerIndex: Int? = nil
    ) {
        let containers = columns(in: workspaceId)
        guard !containers.isEmpty else { return }

        for container in containers {
            switch orientation {
            case .horizontal:
                if container.cachedWidth <= 0 {
                    container.resolveAndCacheWidth(
                        workingAreaWidth: workingFrame.width,
                        gaps: gaps
                    )
                }
            case .vertical:
                if container.cachedHeight <= 0 {
                    container.resolveAndCacheHeight(
                        workingAreaHeight: workingFrame.height,
                        gaps: gaps
                    )
                }
            }
        }

        guard let container = column(of: node),
              let targetIdx = columnIndex(of: container, in: workspaceId)
        else {
            return
        }

        let prevIdx = fromContainerIndex ?? state.activeColumnIndex

        let sizeKeyPath: KeyPath<NiriContainer, CGFloat>
        let viewportSpan: CGFloat
        switch orientation {
        case .horizontal:
            sizeKeyPath = \.cachedWidth
            viewportSpan = workingFrame.width
        case .vertical:
            sizeKeyPath = \.cachedHeight
            viewportSpan = workingFrame.height
        }

        let oldActivePos = state.containerPosition(at: state.activeColumnIndex, containers: containers, gap: gaps, sizeKeyPath: sizeKeyPath)
        let newActivePos = state.containerPosition(at: targetIdx, containers: containers, gap: gaps, sizeKeyPath: sizeKeyPath)
        state.viewOffsetPixels.offset(delta: Double(oldActivePos - newActivePos))

        state.activeColumnIndex = targetIdx
        state.activatePrevColumnOnRemoval = nil
        state.viewOffsetToRestore = nil

        state.ensureContainerVisible(
            containerIndex: targetIdx,
            containers: containers,
            gap: gaps,
            viewportSpan: viewportSpan,
            sizeKeyPath: sizeKeyPath,
            animate: true,
            centerMode: centerFocusedColumn,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn,
            animationConfig: animationConfig,
            fromContainerIndex: prevIdx
        )

        state.selectionProgress = 0.0
    }

    func focusTarget(
        direction: Direction,
        currentSelection: NiriNode,
        in workspaceId: WorkspaceDescriptor.ID,
        state: inout ViewportState,
        workingFrame: CGRect,
        gaps: CGFloat,
        orientation: Monitor.Orientation = .horizontal
    ) -> NiriNode? {
        guard let target = resolveWorkspaceNavigationTargetNode(
            workspaceId: workspaceId,
            op: .focusTarget,
            currentSelection: currentSelection,
            direction: direction,
            orientation: orientation
        )
        else {
            return nil
        }

        ensureSelectionVisible(
            node: target,
            in: workspaceId,
            state: &state,
            workingFrame: workingFrame,
            gaps: gaps,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn,
            orientation: orientation
        )

        return target
    }

    func focusDownOrLeft(
        currentSelection: NiriNode,
        in workspaceId: WorkspaceDescriptor.ID,
        state: inout ViewportState,
        workingFrame: CGRect,
        gaps: CGFloat
    ) -> NiriNode? {
        guard let target = resolveWorkspaceNavigationTargetNode(
            workspaceId: workspaceId,
            op: .focusDownOrLeft,
            currentSelection: currentSelection
        )
        else {
            return nil
        }

        ensureSelectionVisible(
            node: target,
            in: workspaceId,
            state: &state,
            workingFrame: workingFrame,
            gaps: gaps,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn
        )

        return target
    }

    func focusUpOrRight(
        currentSelection: NiriNode,
        in workspaceId: WorkspaceDescriptor.ID,
        state: inout ViewportState,
        workingFrame: CGRect,
        gaps: CGFloat
    ) -> NiriNode? {
        guard let target = resolveWorkspaceNavigationTargetNode(
            workspaceId: workspaceId,
            op: .focusUpOrRight,
            currentSelection: currentSelection
        )
        else {
            return nil
        }

        ensureSelectionVisible(
            node: target,
            in: workspaceId,
            state: &state,
            workingFrame: workingFrame,
            gaps: gaps,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn
        )

        return target
    }

    func focusColumnFirst(
        currentSelection: NiriNode,
        in workspaceId: WorkspaceDescriptor.ID,
        state: inout ViewportState,
        workingFrame: CGRect,
        gaps: CGFloat
    ) -> NiriNode? {
        state.activatePrevColumnOnRemoval = nil

        guard let target = resolveWorkspaceNavigationTargetNode(
            workspaceId: workspaceId,
            op: .focusColumnFirst,
            currentSelection: currentSelection,
            allowMissingSelection: true
        )
        else {
            return nil
        }

        ensureSelectionVisible(
            node: target,
            in: workspaceId,
            state: &state,
            workingFrame: workingFrame,
            gaps: gaps,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn
        )

        return target
    }

    func focusColumnLast(
        currentSelection: NiriNode,
        in workspaceId: WorkspaceDescriptor.ID,
        state: inout ViewportState,
        workingFrame: CGRect,
        gaps: CGFloat
    ) -> NiriNode? {
        state.activatePrevColumnOnRemoval = nil

        guard let target = resolveWorkspaceNavigationTargetNode(
            workspaceId: workspaceId,
            op: .focusColumnLast,
            currentSelection: currentSelection,
            allowMissingSelection: true
        )
        else {
            return nil
        }

        ensureSelectionVisible(
            node: target,
            in: workspaceId,
            state: &state,
            workingFrame: workingFrame,
            gaps: gaps,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn
        )

        return target
    }

    func focusColumn(
        _ columnIndex: Int,
        currentSelection: NiriNode,
        in workspaceId: WorkspaceDescriptor.ID,
        state: inout ViewportState,
        workingFrame: CGRect,
        gaps: CGFloat
    ) -> NiriNode? {
        guard let runtimeView = runtimeWorkspaceView(for: workspaceId),
              runtimeView.columns.indices.contains(columnIndex)
        else {
            return nil
        }

        state.activatePrevColumnOnRemoval = nil

        guard let target = resolveWorkspaceNavigationTargetNode(
            workspaceId: workspaceId,
            op: .focusColumnIndex,
            currentSelection: currentSelection,
            focusColumnIndex: columnIndex,
            allowMissingSelection: true
        )
        else {
            return nil
        }

        ensureSelectionVisible(
            node: target,
            in: workspaceId,
            state: &state,
            workingFrame: workingFrame,
            gaps: gaps,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn
        )

        return target
    }

    func focusWindowInColumn(
        _ windowIndex: Int,
        currentSelection: NiriNode,
        in workspaceId: WorkspaceDescriptor.ID,
        state: inout ViewportState,
        workingFrame: CGRect,
        gaps: CGFloat
    ) -> NiriNode? {
        guard let target = resolveWorkspaceNavigationTargetNode(
            workspaceId: workspaceId,
            op: .focusWindowIndex,
            currentSelection: currentSelection,
            focusWindowIndex: windowIndex
        )
        else {
            return nil
        }

        ensureSelectionVisible(
            node: target,
            in: workspaceId,
            state: &state,
            workingFrame: workingFrame,
            gaps: gaps,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn
        )

        return target
    }

    func focusWindowTop(
        currentSelection: NiriNode,
        in workspaceId: WorkspaceDescriptor.ID,
        state: inout ViewportState,
        workingFrame: CGRect,
        gaps: CGFloat
    ) -> NiriNode? {
        guard let target = resolveWorkspaceNavigationTargetNode(
            workspaceId: workspaceId,
            op: .focusWindowTop,
            currentSelection: currentSelection
        )
        else {
            return nil
        }

        ensureSelectionVisible(
            node: target,
            in: workspaceId,
            state: &state,
            workingFrame: workingFrame,
            gaps: gaps,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn
        )

        return target
    }

    func focusWindowBottom(
        currentSelection: NiriNode,
        in workspaceId: WorkspaceDescriptor.ID,
        state: inout ViewportState,
        workingFrame: CGRect,
        gaps: CGFloat
    ) -> NiriNode? {
        guard let target = resolveWorkspaceNavigationTargetNode(
            workspaceId: workspaceId,
            op: .focusWindowBottom,
            currentSelection: currentSelection
        )
        else {
            return nil
        }

        ensureSelectionVisible(
            node: target,
            in: workspaceId,
            state: &state,
            workingFrame: workingFrame,
            gaps: gaps,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn
        )

        return target
    }

    func focusPrevious(
        currentNodeId: NodeId?,
        in workspaceId: WorkspaceDescriptor.ID,
        state: inout ViewportState,
        workingFrame: CGRect,
        gaps: CGFloat,
        limitToWorkspace: Bool = true
    ) -> NiriWindow? {
        let searchWorkspaceId = limitToWorkspace ? workspaceId : nil
        guard let previousWindow = findMostRecentlyFocusedWindow(
            excluding: currentNodeId,
            in: searchWorkspaceId
        ) else {
            return nil
        }

        state.activatePrevColumnOnRemoval = nil

        ensureSelectionVisible(
            node: previousWindow,
            in: workspaceId,
            state: &state,
            workingFrame: workingFrame,
            gaps: gaps,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn
        )

        return previousWindow
    }
}
