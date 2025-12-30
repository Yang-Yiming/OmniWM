import Foundation
import ApplicationServices

struct MenuItemModel: Identifiable {
    let id: UUID
    let title: String
    let fullPath: String
    let keyboardShortcut: String?
    let isEnabled: Bool
    let axElement: AXUIElement
    let depth: Int
    let parentTitles: [String]

    init(
        title: String,
        fullPath: String,
        keyboardShortcut: String?,
        isEnabled: Bool,
        axElement: AXUIElement,
        depth: Int,
        parentTitles: [String]
    ) {
        self.id = UUID()
        self.title = title
        self.fullPath = fullPath
        self.keyboardShortcut = keyboardShortcut
        self.isEnabled = isEnabled
        self.axElement = axElement
        self.depth = depth
        self.parentTitles = parentTitles
    }
}

enum MenuAnywherePosition: String, CaseIterable, Codable {
    case cursor
    case centered
    case menuBarLocation

    var displayName: String {
        switch self {
        case .cursor: "At Cursor"
        case .centered: "Center of Screen"
        case .menuBarLocation: "Menu Bar Location"
        }
    }
}
