import Foundation
import CoreGraphics

struct DwindleGapCalculator {
    static let sticksTolerance: CGFloat = 2.0

    static func applyGaps(
        nodeRect: CGRect,
        tilingArea: CGRect,
        settings: DwindleSettings
    ) -> CGRect {
        let atLeft = abs(nodeRect.minX - tilingArea.minX) < sticksTolerance
        let atRight = abs(nodeRect.maxX - tilingArea.maxX) < sticksTolerance
        let atBottom = abs(nodeRect.minY - tilingArea.minY) < sticksTolerance
        let atTop = abs(nodeRect.maxY - tilingArea.maxY) < sticksTolerance

        let leftGap = atLeft ? settings.outerGapLeft : settings.innerGap / 2
        let rightGap = atRight ? settings.outerGapRight : settings.innerGap / 2
        let bottomGap = atBottom ? settings.outerGapBottom : settings.innerGap / 2
        let topGap = atTop ? settings.outerGapTop : settings.innerGap / 2

        return CGRect(
            x: nodeRect.minX + leftGap,
            y: nodeRect.minY + bottomGap,
            width: max(1, nodeRect.width - leftGap - rightGap),
            height: max(1, nodeRect.height - topGap - bottomGap)
        )
    }

    static func applyOuterGapsOnly(
        rect: CGRect,
        settings: DwindleSettings
    ) -> CGRect {
        CGRect(
            x: rect.minX + settings.outerGapLeft,
            y: rect.minY + settings.outerGapBottom,
            width: max(1, rect.width - settings.outerGapLeft - settings.outerGapRight),
            height: max(1, rect.height - settings.outerGapTop - settings.outerGapBottom)
        )
    }
}
