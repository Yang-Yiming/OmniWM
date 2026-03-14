import AppKit
import Foundation

@MainActor
final class OwnedWindowRegistry {
    static let shared = OwnedWindowRegistry()

    private let windows = NSHashTable<NSWindow>.weakObjects()

    func register(_ window: NSWindow) {
        windows.add(window)
    }

    func unregister(_ window: NSWindow) {
        windows.remove(window)
    }

    func contains(point: CGPoint) -> Bool {
        visibleWindows.contains { $0.frame.contains(point) }
    }

    func contains(window: NSWindow?) -> Bool {
        guard let window else { return false }
        return visibleWindows.contains { $0 === window }
    }

    var hasFrontmostWindow: Bool {
        guard let app = NSApp else { return false }
        return contains(window: app.keyWindow) || contains(window: app.mainWindow)
    }

    var hasVisibleWindow: Bool {
        !visibleWindows.isEmpty
    }

    func resetForTests() {
        windows.removeAllObjects()
    }

    private var visibleWindows: [NSWindow] {
        windows.allObjects.filter(\.isVisible)
    }
}
