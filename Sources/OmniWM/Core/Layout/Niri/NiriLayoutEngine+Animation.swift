import AppKit
import Foundation

extension NiriLayoutEngine {
    struct ColumnRemovalResult {
        let fallbackSelectionId: NodeId?
        let restorePreviousViewOffset: CGFloat?
    }

    func animateColumnsForRemoval(
        columnIndex removedIdx: Int,
        in workspaceId: WorkspaceDescriptor.ID,
        state: inout ViewportState,
        gaps: CGFloat
    ) -> ColumnRemovalResult {
        let cols = columns(in: workspaceId)
        guard removedIdx >= 0, removedIdx < cols.count else {
            return ColumnRemovalResult(
                fallbackSelectionId: nil,
                restorePreviousViewOffset: nil
            )
        }

        let activeIdx = state.activeColumnIndex
        let offset = columnX(at: removedIdx + 1, columns: cols, gaps: gaps)
                   - columnX(at: removedIdx, columns: cols, gaps: gaps)
        let postRemovalCount = cols.count - 1

        if activeIdx <= removedIdx {
            for col in cols[(removedIdx + 1)...] {
                if col.hasMoveAnimationRunning {
                    col.offsetMoveAnimCurrent(offset)
                } else {
                    col.animateMoveFrom(
                        displacement: CGPoint(x: offset, y: 0),
                        clock: animationClock,
                        config: windowMovementAnimationConfig,
                        displayRefreshRate: displayRefreshRate
                    )
                }
            }
        } else {
            for col in cols[..<removedIdx] {
                if col.hasMoveAnimationRunning {
                    col.offsetMoveAnimCurrent(-offset)
                } else {
                    col.animateMoveFrom(
                        displacement: CGPoint(x: -offset, y: 0),
                        clock: animationClock,
                        config: windowMovementAnimationConfig,
                        displayRefreshRate: displayRefreshRate
                    )
                }
            }
        }

        let removingNode = cols[removedIdx].windowNodes.first
        let fallback = removingNode.flatMap { fallbackSelectionOnRemoval(removing: $0.id, in: workspaceId) }

        if removedIdx < activeIdx {
            state.activeColumnIndex = activeIdx - 1
            state.viewOffsetPixels.offset(delta: Double(offset))
            state.activatePrevColumnOnRemoval = nil
            return ColumnRemovalResult(
                fallbackSelectionId: fallback,
                restorePreviousViewOffset: nil
            )
        } else if removedIdx == activeIdx,
                  let prevOffset = state.activatePrevColumnOnRemoval {
            let newActiveIdx = max(0, activeIdx - 1)
            state.activeColumnIndex = newActiveIdx
            state.activatePrevColumnOnRemoval = nil
            return ColumnRemovalResult(
                fallbackSelectionId: fallback,
                restorePreviousViewOffset: prevOffset
            )
        } else if removedIdx == activeIdx {
            let newActiveIdx = min(activeIdx, max(0, postRemovalCount - 1))
            state.activeColumnIndex = newActiveIdx
            state.activatePrevColumnOnRemoval = nil
            return ColumnRemovalResult(
                fallbackSelectionId: fallback,
                restorePreviousViewOffset: nil
            )
        } else {
            state.activatePrevColumnOnRemoval = nil
            return ColumnRemovalResult(
                fallbackSelectionId: fallback,
                restorePreviousViewOffset: nil
            )
        }
    }

    func animateColumnsForAddition(
        columnIndex addedIdx: Int,
        in workspaceId: WorkspaceDescriptor.ID,
        state: ViewportState,
        gaps: CGFloat,
        workingAreaWidth: CGFloat
    ) {
        let cols = columns(in: workspaceId)
        guard addedIdx >= 0, addedIdx < cols.count else { return }

        let addedCol = cols[addedIdx]
        let activeIdx = state.activeColumnIndex

        if addedCol.cachedWidth <= 0 {
            addedCol.resolveAndCacheWidth(workingAreaWidth: workingAreaWidth, gaps: gaps)
        }

        let offset = addedCol.cachedWidth + gaps

        if activeIdx <= addedIdx {
            for col in cols[(addedIdx + 1)...] {
                if col.hasMoveAnimationRunning {
                    col.offsetMoveAnimCurrent(-offset)
                } else {
                    col.animateMoveFrom(
                        displacement: CGPoint(x: -offset, y: 0),
                        clock: animationClock,
                        config: windowMovementAnimationConfig,
                        displayRefreshRate: displayRefreshRate
                    )
                }
            }
        } else {
            for col in cols[..<addedIdx] {
                if col.hasMoveAnimationRunning {
                    col.offsetMoveAnimCurrent(offset)
                } else {
                    col.animateMoveFrom(
                        displacement: CGPoint(x: offset, y: 0),
                        clock: animationClock,
                        config: windowMovementAnimationConfig,
                        displayRefreshRate: displayRefreshRate
                    )
                }
            }
        }
    }

    func tickAllColumnAnimations(in workspaceId: WorkspaceDescriptor.ID, at time: TimeInterval) -> Bool {
        guard let root = roots[workspaceId] else { return false }
        var anyRunning = false
        for column in root.columns {
            if column.tickMoveAnimation(at: time) { anyRunning = true }
            if column.tickWidthAnimation(at: time) { anyRunning = true }
        }
        return anyRunning
    }

    func tickWorkspaceSwitchAnimation(for workspaceId: WorkspaceDescriptor.ID, at time: TimeInterval) -> Bool {
        guard let monitorId = monitorContaining(workspace: workspaceId),
              let monitor = monitors[monitorId] else {
            return false
        }
        return monitor.tickWorkspaceSwitchAnimation(at: time)
    }

    func hasAnyColumnAnimationsRunning(in workspaceId: WorkspaceDescriptor.ID) -> Bool {
        guard let root = roots[workspaceId] else { return false }
        return root.columns.contains { $0.hasMoveAnimationRunning || $0.hasWidthAnimationRunning }
    }

    func calculateCombinedLayout(
        in workspaceId: WorkspaceDescriptor.ID,
        monitor: Monitor,
        gaps: LayoutGaps,
        state: ViewportState,
        workingArea: WorkingAreaContext? = nil,
        animationTime: TimeInterval? = nil
    ) -> [WindowHandle: CGRect] {
        calculateCombinedLayoutWithVisibility(
            in: workspaceId,
            monitor: monitor,
            gaps: gaps,
            state: state,
            workingArea: workingArea,
            animationTime: animationTime
        ).frames
    }

    func calculateCombinedLayoutWithVisibility(
        in workspaceId: WorkspaceDescriptor.ID,
        monitor: Monitor,
        gaps: LayoutGaps,
        state: ViewportState,
        workingArea: WorkingAreaContext? = nil,
        animationTime: TimeInterval? = nil
    ) -> LayoutResult {
        let area = workingArea ?? WorkingAreaContext(
            workingFrame: monitor.visibleFrame,
            viewFrame: monitor.frame,
            scale: 2.0
        )

        let orientation = self.monitor(for: monitor.id)?.orientation ?? monitor.autoOrientation

        return calculateLayoutWithVisibility(
            state: state,
            workspaceId: workspaceId,
            monitorFrame: monitor.visibleFrame,
            screenFrame: monitor.frame,
            gaps: gaps.asTuple,
            scale: area.scale,
            workingArea: area,
            orientation: orientation,
            animationTime: animationTime
        )
    }

    func calculateCombinedLayoutUsingPools(
        in workspaceId: WorkspaceDescriptor.ID,
        monitor: Monitor,
        gaps: LayoutGaps,
        state: ViewportState,
        workingArea: WorkingAreaContext? = nil,
        animationTime: TimeInterval? = nil
    ) -> (frames: [WindowHandle: CGRect], hiddenHandles: [WindowHandle: HideSide]) {
        framePool.removeAll(keepingCapacity: true)
        hiddenPool.removeAll(keepingCapacity: true)

        let area = workingArea ?? WorkingAreaContext(
            workingFrame: monitor.visibleFrame,
            viewFrame: monitor.frame,
            scale: 2.0
        )

        let orientation = self.monitor(for: monitor.id)?.orientation ?? monitor.autoOrientation

        calculateLayoutInto(
            frames: &framePool,
            hiddenHandles: &hiddenPool,
            state: state,
            workspaceId: workspaceId,
            monitorFrame: monitor.visibleFrame,
            screenFrame: monitor.frame,
            gaps: gaps.asTuple,
            scale: area.scale,
            workingArea: area,
            orientation: orientation,
            animationTime: animationTime
        )

        return (framePool, hiddenPool)
    }

    func captureWindowFrames(in workspaceId: WorkspaceDescriptor.ID) -> [WindowHandle: CGRect] {
        guard let root = root(for: workspaceId) else { return [:] }
        var frames: [WindowHandle: CGRect] = [:]
        for window in root.allWindows {
            if let frame = window.frame {
                frames[window.handle] = frame
            }
        }
        return frames
    }

    func triggerMoveAnimations(
        in workspaceId: WorkspaceDescriptor.ID,
        oldFrames: [WindowHandle: CGRect],
        newFrames: [WindowHandle: CGRect],
        threshold: CGFloat = 1.0
    ) -> Bool {
        guard let root = root(for: workspaceId) else { return false }
        var anyAnimationStarted = false

        for window in root.allWindows {
            guard let oldFrame = oldFrames[window.handle],
                  let newFrame = newFrames[window.handle]
            else {
                continue
            }

            let dx = oldFrame.origin.x - newFrame.origin.x
            let dy = oldFrame.origin.y - newFrame.origin.y

            if abs(dx) > threshold || abs(dy) > threshold {
                window.animateMoveFrom(
                    displacement: CGPoint(x: dx, y: dy),
                    clock: animationClock,
                    config: windowMovementAnimationConfig,
                    displayRefreshRate: displayRefreshRate
                )
                anyAnimationStarted = true
            }
        }

        return anyAnimationStarted
    }

    func hasAnyWindowAnimationsRunning(in workspaceId: WorkspaceDescriptor.ID) -> Bool {
        guard let root = root(for: workspaceId) else { return false }
        return root.allWindows.contains { $0.hasMoveAnimationsRunning }
    }

    func tickAllWindowAnimations(in workspaceId: WorkspaceDescriptor.ID, at time: TimeInterval) -> Bool {
        guard let root = root(for: workspaceId) else { return false }
        var anyRunning = false
        for window in root.allWindows {
            if window.tickMoveAnimations(at: time) {
                anyRunning = true
            }
        }
        return anyRunning
    }

    func computeTileOffset(column: NiriContainer, tileIdx: Int, gaps: CGFloat) -> CGFloat {
        let windows = column.windowNodes
        guard tileIdx > 0, tileIdx < windows.count else { return 0 }

        var offset: CGFloat = 0
        for i in 0 ..< tileIdx {
            let height = windows[i].resolvedHeight ?? windows[i].frame?.height ?? 0
            offset += height
            offset += gaps
        }
        return offset
    }

    func computeTileOffsets(column: NiriContainer, gaps: CGFloat) -> [CGFloat] {
        let windows = column.windowNodes
        guard !windows.isEmpty else { return [] }

        var offsets: [CGFloat] = [0]
        var y: CGFloat = 0
        for i in 0 ..< windows.count - 1 {
            let height = windows[i].resolvedHeight ?? windows[i].frame?.height ?? 0
            y += height + gaps
            offsets.append(y)
        }
        return offsets
    }

    func tilesOrigin(column: NiriContainer) -> CGPoint {
        let xOffset = column.isTabbed ? renderStyle.tabIndicatorWidth : 0
        return CGPoint(x: xOffset, y: 0)
    }
}
