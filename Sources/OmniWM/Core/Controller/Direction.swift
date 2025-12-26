import AppKit

enum Direction: String, Codable {
    case left, right, up, down

    var displayName: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .up: "Up"
        case .down: "Down"
        }
    }
}

extension ScrollModifierKey {
    var eventModifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .option: .option
        case .control: .control
        case .command: .command
        }
    }
}
