import AppKit
import Foundation

extension CGPoint {
    func flipY(maxY: CGFloat) -> CGPoint {
        CGPoint(x: x, y: maxY - y)
    }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }

    func approximatelyEqual(to other: CGRect, tolerance: CGFloat = 10) -> Bool {
        abs(origin.x - other.origin.x) < tolerance &&
        abs(origin.y - other.origin.y) < tolerance &&
        abs(width - other.width) < tolerance &&
        abs(height - other.height) < tolerance
    }
}

enum ScreenCoordinateSpace {
    private struct ScreenTransform {
        let appKitFrame: CGRect
        let quartzFrame: CGRect

        func toAppKit(point: CGPoint) -> CGPoint {
            let dx = point.x - quartzFrame.minX
            let dy = point.y - quartzFrame.minY
            return CGPoint(x: appKitFrame.minX + dx, y: appKitFrame.maxY - dy)
        }

        func toWindowServer(point: CGPoint) -> CGPoint {
            let dx = point.x - appKitFrame.minX
            let dy = appKitFrame.maxY - point.y
            return CGPoint(x: quartzFrame.minX + dx, y: quartzFrame.minY + dy)
        }

        func toAppKit(rect: CGRect) -> CGRect {
            let dx = rect.origin.x - quartzFrame.minX
            let dy = rect.origin.y - quartzFrame.minY
            let x = appKitFrame.minX + dx
            let y = appKitFrame.maxY - dy - rect.size.height
            return CGRect(origin: CGPoint(x: x, y: y), size: rect.size)
        }

        func toWindowServer(rect: CGRect) -> CGRect {
            let dx = rect.origin.x - appKitFrame.minX
            let dy = appKitFrame.maxY - rect.origin.y - rect.size.height
            let x = quartzFrame.minX + dx
            let y = quartzFrame.minY + dy
            return CGRect(origin: CGPoint(x: x, y: y), size: rect.size)
        }
    }

    nonisolated(unsafe) private static var cachedTransforms: [ScreenTransform]?
    nonisolated(unsafe) private static var cachedGlobalFrame: CGRect?
    nonisolated(unsafe) private static var screenConfigurationToken: Int = 0

    private static func currentToken() -> Int {
        var hasher = Hasher()
        for screen in NSScreen.screens {
            hasher.combine(screen.displayId ?? 0)
            let frame = screen.frame
            hasher.combine(frame.origin.x)
            hasher.combine(frame.origin.y)
            hasher.combine(frame.size.width)
            hasher.combine(frame.size.height)
        }
        return hasher.finalize()
    }

    private static func transforms() -> [ScreenTransform] {
        let token = currentToken()
        if let cached = cachedTransforms, token == screenConfigurationToken {
            return cached
        }

        let transforms = NSScreen.screens.compactMap { screen -> ScreenTransform? in
            guard let displayId = screen.displayId else { return nil }
            let quartzFrame = CGDisplayBounds(displayId)
            return ScreenTransform(appKitFrame: screen.frame, quartzFrame: quartzFrame)
        }

        cachedTransforms = transforms
        cachedGlobalFrame = nil
        screenConfigurationToken = token
        return transforms
    }

    static var globalFrame: CGRect {
        let token = currentToken()
        if let cached = cachedGlobalFrame, token == screenConfigurationToken {
            return cached
        }
        let frame = NSScreen.screens.reduce(into: CGRect.null) { result, screen in
            result = result.union(screen.frame)
        }
        cachedGlobalFrame = frame
        screenConfigurationToken = token
        return frame
    }

    private static func transformForQuartz(point: CGPoint) -> ScreenTransform? {
        transforms().first { $0.quartzFrame.contains(point) }
    }

    private static func transformForAppKit(point: CGPoint) -> ScreenTransform? {
        transforms().first { $0.appKitFrame.contains(point) }
    }

    static func toAppKit(point: CGPoint) -> CGPoint {
        if let transform = transformForQuartz(point: point) {
            return transform.toAppKit(point: point)
        }
        let global = globalFrame
        return CGPoint(x: point.x, y: global.maxY - point.y)
    }

    static func toAppKit(rect: CGRect) -> CGRect {
        if let transform = transformForQuartz(point: rect.center) {
            return transform.toAppKit(rect: rect)
        }
        let global = globalFrame
        let flippedY = global.maxY - (rect.origin.y + rect.size.height)
        return CGRect(origin: CGPoint(x: rect.origin.x, y: flippedY), size: rect.size)
    }

    static func toWindowServer(point: CGPoint) -> CGPoint {
        if let transform = transformForAppKit(point: point) {
            return transform.toWindowServer(point: point)
        }
        let global = globalFrame
        return CGPoint(x: point.x, y: global.maxY - point.y)
    }

    static func toWindowServer(rect: CGRect) -> CGRect {
        if let transform = transformForAppKit(point: rect.center) {
            return transform.toWindowServer(rect: rect)
        }
        let global = globalFrame
        let flippedY = global.maxY - (rect.origin.y + rect.size.height)
        return CGRect(origin: CGPoint(x: rect.origin.x, y: flippedY), size: rect.size)
    }
}

extension NSScreen {
    static func screen(containing point: CGPoint) -> NSScreen? {
        screens.first(where: { $0.frame.contains(point) })
    }

    static func screen(containing rect: CGRect) -> NSScreen? {
        screens.first(where: { $0.frame.intersects(rect) })
            ?? screen(containing: rect.center)
    }
}
