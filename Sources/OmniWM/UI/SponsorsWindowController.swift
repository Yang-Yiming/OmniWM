import AppKit
import SwiftUI

@MainActor
final class SponsorsWindowController {
    static let shared = SponsorsWindowController()

    private var window: NSWindow?
    private let ownedWindowRegistry = OwnedWindowRegistry.shared

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let sponsorsView = SponsorsView(onClose: { [weak self] in
            self?.window?.close()
        })

        let hosting = NSHostingController(rootView: sponsorsView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Omni Sponsors"
        window.styleMask = [.titled, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.setContentSize(NSSize(width: 700, height: 400))
        window.center()
        window.isReleasedWhenClosed = false
        ownedWindowRegistry.register(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NotificationCenter.default
            .addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.ownedWindowRegistry.unregister(window)
                    self?.window = nil
                }
            }
        self.window = window
    }

    var windowForTests: NSWindow? {
        window
    }

    func isPointInside(_ point: CGPoint) -> Bool {
        guard let window, window.isVisible else { return false }
        return window.frame.contains(point)
    }
}
