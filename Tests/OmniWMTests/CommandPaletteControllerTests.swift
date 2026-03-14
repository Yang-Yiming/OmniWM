import Foundation
import Testing

@testable import OmniWM

private func makeCommandPaletteTestDefaults() -> UserDefaults {
    let suiteName = "com.omniwm.commandpalette.test.\(UUID().uuidString)"
    return UserDefaults(suiteName: suiteName)!
}

@MainActor
private func makeCommandPaletteTestWMController() -> WMController {
    WMController(settings: SettingsStore(defaults: makeCommandPaletteTestDefaults()))
}

private func makeCommandPaletteWindowItem(windowId: Int) -> CommandPaletteWindowItem {
    let handle = WindowHandle(id: WindowToken(pid: 4242, windowId: windowId))
    return CommandPaletteWindowItem(
        id: handle.id,
        handle: handle,
        title: "Window \(windowId)",
        appName: "Test App",
        appIcon: nil,
        workspaceName: "1"
    )
}

private func makeCommandPaletteAppSnapshot(
    pid: pid_t,
    bundleIdentifier: String?,
    localizedName: String?,
    isTerminated: Bool = false
) -> CommandPaletteAppSnapshot {
    CommandPaletteAppSnapshot(
        processIdentifier: pid,
        bundleIdentifier: bundleIdentifier,
        localizedName: localizedName,
        isTerminated: isTerminated
    )
}

@Suite @MainActor struct CommandPaletteControllerTests {
    @Test func selectCurrentNavigatesSelectedWindowAfterDismiss() {
        var navigatedHandle: WindowHandle?
        var environment = CommandPaletteEnvironment()
        environment.navigateToWindow = { _, handle in
            navigatedHandle = handle
        }

        let controller = CommandPaletteController(environment: environment)
        let wmController = makeCommandPaletteTestWMController()
        let item = makeCommandPaletteWindowItem(windowId: 101)

        controller.setWindowSelectionStateForTests(
            wmController: wmController,
            items: [item],
            selectedItemID: .window(item.id)
        )

        controller.selectCurrent()

        #expect(navigatedHandle == item.handle)
        #expect(controller.selectedItemID == nil)
        #expect(controller.filteredWindowItems.isEmpty)
    }

    @Test func selectCurrentUsesUpdatedWindowSelection() {
        var navigatedHandle: WindowHandle?
        var environment = CommandPaletteEnvironment()
        environment.navigateToWindow = { _, handle in
            navigatedHandle = handle
        }

        let controller = CommandPaletteController(environment: environment)
        let wmController = makeCommandPaletteTestWMController()
        let first = makeCommandPaletteWindowItem(windowId: 101)
        let second = makeCommandPaletteWindowItem(windowId: 202)

        controller.setWindowSelectionStateForTests(
            wmController: wmController,
            items: [first, second],
            selectedItemID: .window(second.id)
        )

        controller.selectCurrent()

        #expect(navigatedHandle == second.handle)
    }

    @Test func resolveMenuTargetPrefersCurrentExternalApp() {
        let current = makeCommandPaletteAppSnapshot(
            pid: 200,
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari"
        )
        let cached = makeCommandPaletteAppSnapshot(
            pid: 201,
            bundleIdentifier: "com.apple.TextEdit",
            localizedName: "TextEdit"
        )

        let resolved = CommandPaletteController.resolveMenuTarget(
            current: current,
            cached: cached,
            ownBundleIdentifier: "com.omniwm"
        )

        #expect(resolved == current)
    }

    @Test func resolveMenuTargetFallsBackToCachedExternalAppWhenCurrentIsOmniWM() {
        let current = makeCommandPaletteAppSnapshot(
            pid: 300,
            bundleIdentifier: "com.omniwm",
            localizedName: "OmniWM"
        )
        let cached = makeCommandPaletteAppSnapshot(
            pid: 301,
            bundleIdentifier: "com.apple.Finder",
            localizedName: "Finder"
        )

        let resolved = CommandPaletteController.resolveMenuTarget(
            current: current,
            cached: cached,
            ownBundleIdentifier: "com.omniwm"
        )

        #expect(resolved == cached)
    }

    @Test func resolveMenuTargetIgnoresTerminatedCachedApp() {
        let current = makeCommandPaletteAppSnapshot(
            pid: 400,
            bundleIdentifier: "com.omniwm",
            localizedName: "OmniWM"
        )
        let cached = makeCommandPaletteAppSnapshot(
            pid: 401,
            bundleIdentifier: "com.apple.Terminal",
            localizedName: "Terminal",
            isTerminated: true
        )

        let resolved = CommandPaletteController.resolveMenuTarget(
            current: current,
            cached: cached,
            ownBundleIdentifier: "com.omniwm"
        )

        #expect(resolved == nil)
    }

    @Test func command2SwitchesOnlyWhenMenuModeIsAvailable() {
        let controller = CommandPaletteController()
        controller.selectedMode = .windows
        controller.setMenuAvailabilityForTests(nil)

        #expect(controller.handleModeShortcutForTests("2") == false)
        #expect(controller.selectedMode == .windows)

        controller.setMenuAvailabilityForTests(
            makeCommandPaletteAppSnapshot(
                pid: 500,
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari"
            )
        )

        #expect(controller.handleModeShortcutForTests("2") == true)
        #expect(controller.selectedMode == .menu)
    }

    @Test func windowsStatusTextReflectsMenuAvailability() {
        #expect(
            CommandPaletteController.windowsStatusText(isMenuModeAvailable: true)
                == "Use Command-1 for windows and Command-2 for menu search."
        )
        #expect(
            CommandPaletteController.windowsStatusText(isMenuModeAvailable: false)
                == "Menu search becomes available after you open the palette while another app is frontmost."
        )
    }
}
