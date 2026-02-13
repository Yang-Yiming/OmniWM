import Foundation

extension ViewportState {
    func columnX(at index: Int, columns: [NiriContainer], gap: CGFloat) -> CGFloat {
        containerPosition(at: index, containers: columns, gap: gap, sizeKeyPath: \.cachedWidth)
    }

    func totalWidth(columns: [NiriContainer], gap: CGFloat) -> CGFloat {
        totalSpan(containers: columns, gap: gap, sizeKeyPath: \.cachedWidth)
    }

    func containerPosition(at index: Int, containers: [NiriContainer], gap: CGFloat, sizeKeyPath: KeyPath<NiriContainer, CGFloat>) -> CGFloat {
        var pos: CGFloat = 0
        for i in 0 ..< index {
            guard i < containers.count else { break }
            pos += containers[i][keyPath: sizeKeyPath] + gap
        }
        return pos
    }

    func totalSpan(containers: [NiriContainer], gap: CGFloat, sizeKeyPath: KeyPath<NiriContainer, CGFloat>) -> CGFloat {
        guard !containers.isEmpty else { return 0 }
        let sizeSum = containers.reduce(0) { $0 + $1[keyPath: sizeKeyPath] }
        let gapSum = CGFloat(max(0, containers.count - 1)) * gap
        return sizeSum + gapSum
    }

    func computeCenteredOffset(containerIndex: Int, containers: [NiriContainer], gap: CGFloat, viewportSpan: CGFloat, sizeKeyPath: KeyPath<NiriContainer, CGFloat>) -> CGFloat {
        guard !containers.isEmpty, containerIndex < containers.count else { return 0 }

        let total = totalSpan(containers: containers, gap: gap, sizeKeyPath: sizeKeyPath)

        if total <= viewportSpan {
            let pos = containerPosition(at: containerIndex, containers: containers, gap: gap, sizeKeyPath: sizeKeyPath)
            return -pos - (viewportSpan - total) / 2
        }

        let containerSize = containers[containerIndex][keyPath: sizeKeyPath]
        let centeredOffset = -(viewportSpan - containerSize) / 2

        let maxOffset: CGFloat = 0
        let minOffset = viewportSpan - total

        return centeredOffset.clamped(to: minOffset ... maxOffset)
    }

    private func computeFitOffset(currentViewPos: CGFloat, viewSpan: CGFloat, targetPos: CGFloat, targetSpan: CGFloat, gaps: CGFloat) -> CGFloat {
        if viewSpan <= targetSpan {
            return 0
        }

        let padding = ((viewSpan - targetSpan) / 2).clamped(to: 0 ... gaps)
        let newPos = targetPos - padding
        let newEndPos = targetPos + targetSpan + padding

        if currentViewPos <= newPos && newEndPos <= currentViewPos + viewSpan {
            return -(targetPos - currentViewPos)
        }

        let distToStart = abs(currentViewPos - newPos)
        let distToEnd = abs((currentViewPos + viewSpan) - newEndPos)

        if distToStart <= distToEnd {
            return -padding
        } else {
            return -(viewSpan - padding - targetSpan)
        }
    }

    func computeVisibleOffset(
        containerIndex: Int,
        containers: [NiriContainer],
        gap: CGFloat,
        viewportSpan: CGFloat,
        sizeKeyPath: KeyPath<NiriContainer, CGFloat>,
        currentViewStart: CGFloat,
        centerMode: CenterFocusedColumn,
        alwaysCenterSingleColumn: Bool = false,
        fromContainerIndex: Int? = nil
    ) -> CGFloat {
        guard !containers.isEmpty, containerIndex >= 0, containerIndex < containers.count else { return 0 }

        let effectiveCenterMode = (containers.count == 1 && alwaysCenterSingleColumn) ? .always : centerMode

        let targetPos = containerPosition(at: containerIndex, containers: containers, gap: gap, sizeKeyPath: sizeKeyPath)
        let targetSize = containers[containerIndex][keyPath: sizeKeyPath]

        var targetOffset: CGFloat

        switch effectiveCenterMode {
        case .always:
            targetOffset = computeCenteredOffset(
                containerIndex: containerIndex,
                containers: containers,
                gap: gap,
                viewportSpan: viewportSpan,
                sizeKeyPath: sizeKeyPath
            )

        case .onOverflow:
            if targetSize > viewportSpan {
                targetOffset = computeCenteredOffset(
                    containerIndex: containerIndex,
                    containers: containers,
                    gap: gap,
                    viewportSpan: viewportSpan,
                    sizeKeyPath: sizeKeyPath
                )
            } else if let fromIdx = fromContainerIndex, fromIdx != containerIndex {
                let sourceIdx = fromIdx > containerIndex
                    ? min(containerIndex + 1, containers.count - 1)
                    : max(containerIndex - 1, 0)

                guard sourceIdx >= 0, sourceIdx < containers.count else {
                    targetOffset = computeFitOffset(
                        currentViewPos: currentViewStart,
                        viewSpan: viewportSpan,
                        targetPos: targetPos,
                        targetSpan: targetSize,
                        gaps: gap
                    )
                    break
                }

                let sourcePos = containerPosition(at: sourceIdx, containers: containers, gap: gap, sizeKeyPath: sizeKeyPath)
                let sourceSize = containers[sourceIdx][keyPath: sizeKeyPath]

                let totalSpanNeeded: CGFloat = if sourcePos < targetPos {
                    targetPos - sourcePos + targetSize + gap * 2
                } else {
                    sourcePos - targetPos + sourceSize + gap * 2
                }

                if totalSpanNeeded <= viewportSpan {
                    targetOffset = computeFitOffset(
                        currentViewPos: currentViewStart,
                        viewSpan: viewportSpan,
                        targetPos: targetPos,
                        targetSpan: targetSize,
                        gaps: gap
                    )
                } else {
                    targetOffset = computeCenteredOffset(
                        containerIndex: containerIndex,
                        containers: containers,
                        gap: gap,
                        viewportSpan: viewportSpan,
                        sizeKeyPath: sizeKeyPath
                    )
                }
            } else {
                targetOffset = computeFitOffset(
                    currentViewPos: currentViewStart,
                    viewSpan: viewportSpan,
                    targetPos: targetPos,
                    targetSpan: targetSize,
                    gaps: gap
                )
            }

        case .never:
            targetOffset = computeFitOffset(
                currentViewPos: currentViewStart,
                viewSpan: viewportSpan,
                targetPos: targetPos,
                targetSpan: targetSize,
                gaps: gap
            )
        }

        let total = totalSpan(containers: containers, gap: gap, sizeKeyPath: sizeKeyPath)
        let maxOffset: CGFloat = 0
        let minOffset = viewportSpan - total
        if minOffset < maxOffset {
            targetOffset = targetOffset.clamped(to: minOffset ... maxOffset)
        }

        return targetOffset
    }

    func computeCenteredOffset(
        columnIndex: Int,
        columns: [NiriContainer],
        gap: CGFloat,
        viewportWidth: CGFloat
    ) -> CGFloat {
        computeCenteredOffset(containerIndex: columnIndex, containers: columns, gap: gap, viewportSpan: viewportWidth, sizeKeyPath: \.cachedWidth)
    }

    func computeVisibleOffset(
        columnIndex: Int,
        columns: [NiriContainer],
        gap: CGFloat,
        viewportWidth: CGFloat,
        currentOffset: CGFloat,
        centerMode: CenterFocusedColumn,
        alwaysCenterSingleColumn: Bool = false,
        fromColumnIndex: Int? = nil
    ) -> CGFloat {
        let colX = columnX(at: columnIndex, columns: columns, gap: gap)
        return computeVisibleOffset(
            containerIndex: columnIndex,
            containers: columns,
            gap: gap,
            viewportSpan: viewportWidth,
            sizeKeyPath: \.cachedWidth,
            currentViewStart: colX + currentOffset,
            centerMode: centerMode,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn,
            fromContainerIndex: fromColumnIndex
        )
    }
}
