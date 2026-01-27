import Cocoa

final class QuakeTerminalWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    var initialFrame: NSRect?
    var isAnimating: Bool = false

    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        setup()
    }

    private func setup() {
        identifier = NSUserInterfaceItemIdentifier(rawValue: "com.omniwm.quakeTerminal")
        setAccessibilitySubrole(.floatingWindow)
        styleMask.remove(.titled)
        styleMask.insert(.nonactivatingPanel)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        if isAnimating {
            super.setFrame(initialFrame ?? frameRect, display: flag)
        } else {
            super.setFrame(frameRect, display: flag)
        }
    }
}
