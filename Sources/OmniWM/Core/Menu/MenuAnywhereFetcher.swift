import AppKit
@preconcurrency import ApplicationServices

@MainActor
final class MenuAnywhereFetcher {
    private var cachedPid: pid_t?
    private var cachedItems: [MenuItemModel]?
    private let menuExtractor = MenuExtractor()

    func fetchMenuItemsSync(for pid: pid_t) -> [MenuItemModel] {
        if cachedPid == pid, let cached = cachedItems {
            return cached
        }

        guard let menuBar = menuExtractor.getMenuBar(for: pid) else {
            return []
        }
        let items = menuExtractor.flattenMenuItems(from: menuBar, appName: nil, excludeAppleMenu: true)

        cachedPid = pid
        cachedItems = items
        return items
    }

    func getMenuBar() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return menuExtractor.getMenuBar(for: app.processIdentifier)
    }

    func invalidateCache() {
        cachedPid = nil
        cachedItems = nil
    }
}
