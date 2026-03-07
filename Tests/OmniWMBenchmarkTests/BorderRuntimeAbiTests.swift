import CZigLayout
import Foundation
import XCTest

@testable import OmniWM

final class BorderRuntimeAbiTests: XCTestCase {
    func testBorderRuntimeSubmitSnapshotHideDestroy() {
        guard let runtime = omni_border_runtime_create() else {
            XCTFail("Expected Zig border runtime to initialize")
            return
        }
        defer { omni_border_runtime_destroy(runtime) }

        var config = OmniBorderConfig(
            enabled: 1,
            width: 4.0,
            color: OmniBorderColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1.0)
        )

        XCTAssertEqual(
            withUnsafePointer(to: &config) { omni_border_runtime_apply_config(runtime, $0) },
            0
        )

        var snapshot = OmniBorderSnapshotInput(
            config: config,
            has_focused_window_id: 0,
            focused_window_id: 0,
            has_focused_frame: 0,
            focused_frame: OmniBorderRect(x: 0, y: 0, width: 0, height: 0),
            is_focused_window_in_active_workspace: 0,
            is_non_managed_focus_active: 0,
            is_native_fullscreen_active: 0,
            is_managed_fullscreen_active: 0,
            defer_updates: 0,
            update_mode: 0,
            layout_animation_active: 0,
            force_hide: 0,
            displays: nil,
            display_count: 0
        )

        XCTAssertEqual(
            withUnsafePointer(to: &snapshot) { omni_border_runtime_submit_snapshot(runtime, $0) },
            0
        )

        snapshot.force_hide = 1
        XCTAssertEqual(
            withUnsafePointer(to: &snapshot) { omni_border_runtime_submit_snapshot(runtime, $0) },
            0
        )
    }

    func testBorderRuntimeSubmitSnapshotAcceptsDeferredDisplayPayload() {
        guard let runtime = omni_border_runtime_create() else {
            XCTFail("Expected Zig border runtime to initialize")
            return
        }
        defer { omni_border_runtime_destroy(runtime) }

        var config = OmniBorderConfig(
            enabled: 1,
            width: 6.0,
            color: OmniBorderColor(red: 0.0, green: 0.5, blue: 1.0, alpha: 1.0)
        )
        XCTAssertEqual(
            withUnsafePointer(to: &config) { omni_border_runtime_apply_config(runtime, $0) },
            0
        )

        let displays = [OmniBorderDisplayInfo(
            display_id: 1,
            appkit_frame: OmniBorderRect(x: 0, y: 0, width: 1440, height: 900),
            window_server_frame: OmniBorderRect(x: 0, y: 0, width: 2880, height: 1800),
            backing_scale: 2.0
        )]

        var snapshot = OmniBorderSnapshotInput(
            config: config,
            has_focused_window_id: 1,
            focused_window_id: 42,
            has_focused_frame: 1,
            focused_frame: OmniBorderRect(x: 100, y: 120, width: 640, height: 480),
            is_focused_window_in_active_workspace: 1,
            is_non_managed_focus_active: 0,
            is_native_fullscreen_active: 0,
            is_managed_fullscreen_active: 0,
            defer_updates: 1,
            update_mode: 0,
            layout_animation_active: 1,
            force_hide: 0,
            displays: nil,
            display_count: displays.count
        )

        let rc = displays.withUnsafeBufferPointer { displayBuffer -> Int32 in
            snapshot.displays = displayBuffer.baseAddress
            return withUnsafePointer(to: &snapshot) {
                omni_border_runtime_submit_snapshot(runtime, $0)
            }
        }

        XCTAssertEqual(rc, 0)
        XCTAssertEqual(omni_border_runtime_invalidate_displays(runtime), 0)
        XCTAssertEqual(omni_border_runtime_hide(runtime), 0)
    }

    func testBorderRuntimeSubmitSnapshotPresentsFocusedWindow() {
        guard let runtime = omni_border_runtime_create() else {
            XCTFail("Expected Zig border runtime to initialize")
            return
        }
        defer { omni_border_runtime_destroy(runtime) }

        var config = OmniBorderConfig(
            enabled: 1,
            width: 5.0,
            color: OmniBorderColor(red: 0.3, green: 0.4, blue: 0.9, alpha: 1.0)
        )
        XCTAssertEqual(
            withUnsafePointer(to: &config) { omni_border_runtime_apply_config(runtime, $0) },
            0
        )

        let displays = [OmniBorderDisplayInfo(
            display_id: 1,
            appkit_frame: OmniBorderRect(x: 0, y: 0, width: 1728, height: 1117),
            window_server_frame: OmniBorderRect(x: 0, y: 0, width: 3456, height: 2234),
            backing_scale: 2.0
        )]

        var snapshot = OmniBorderSnapshotInput(
            config: config,
            has_focused_window_id: 1,
            focused_window_id: 77,
            has_focused_frame: 1,
            focused_frame: OmniBorderRect(x: 240, y: 180, width: 960, height: 720),
            is_focused_window_in_active_workspace: 1,
            is_non_managed_focus_active: 0,
            is_native_fullscreen_active: 0,
            is_managed_fullscreen_active: 0,
            defer_updates: 0,
            update_mode: 1,
            layout_animation_active: 1,
            force_hide: 0,
            displays: nil,
            display_count: displays.count
        )

        let rc = displays.withUnsafeBufferPointer { displayBuffer -> Int32 in
            snapshot.displays = displayBuffer.baseAddress
            return withUnsafePointer(to: &snapshot) {
                omni_border_runtime_submit_snapshot(runtime, $0)
            }
        }

        XCTAssertEqual(rc, 0)
    }

    func testBorderRuntimeCompatibilityWrappersRemainAvailable() {
        guard let runtime = omni_border_runtime_create() else {
            XCTFail("Expected Zig border runtime to initialize")
            return
        }
        defer { omni_border_runtime_destroy(runtime) }

        var config = OmniBorderConfig(
            enabled: 1,
            width: 4.0,
            color: OmniBorderColor(red: 0.0, green: 0.5, blue: 1.0, alpha: 1.0)
        )
        XCTAssertEqual(
            withUnsafePointer(to: &config) { omni_border_runtime_apply_config(runtime, $0) },
            0
        )

        var presentation = OmniBorderPresentationInput(
            config: config,
            has_focused_window_id: 0,
            focused_window_id: 0,
            has_focused_frame: 0,
            focused_frame: OmniBorderRect(x: 0, y: 0, width: 0, height: 0),
            is_focused_window_in_active_workspace: 0,
            is_non_managed_focus_active: 0,
            is_native_fullscreen_active: 0,
            is_managed_fullscreen_active: 0,
            defer_updates: 0,
            update_mode: 0,
            layout_animation_active: 0,
            displays: nil,
            display_count: 0
        )

        XCTAssertEqual(
            withUnsafePointer(to: &presentation) { omni_border_runtime_apply_presentation(runtime, $0) },
            0
        )
    }

    func testBorderAbiStructLayoutRemainsStable() {
        XCTAssertEqual(MemoryLayout<OmniBorderColor>.size, 32)
        XCTAssertEqual(MemoryLayout<OmniBorderColor>.alignment, 8)

        XCTAssertEqual(MemoryLayout<OmniBorderConfig>.size, 48)
        XCTAssertEqual(MemoryLayout<OmniBorderConfig>.alignment, 8)
        assertOffset(OmniBorderConfig.self, \.enabled, equals: 0)
        assertOffset(OmniBorderConfig.self, \.width, equals: 8)
        assertOffset(OmniBorderConfig.self, \.color, equals: 16)

        XCTAssertEqual(MemoryLayout<OmniBorderRect>.size, 32)
        XCTAssertEqual(MemoryLayout<OmniBorderRect>.alignment, 8)

        XCTAssertEqual(MemoryLayout<OmniBorderDisplayInfo>.size, 80)
        XCTAssertEqual(MemoryLayout<OmniBorderDisplayInfo>.alignment, 8)
        assertOffset(OmniBorderDisplayInfo.self, \.display_id, equals: 0)
        assertOffset(OmniBorderDisplayInfo.self, \.appkit_frame, equals: 8)
        assertOffset(OmniBorderDisplayInfo.self, \.window_server_frame, equals: 40)
        assertOffset(OmniBorderDisplayInfo.self, \.backing_scale, equals: 72)

        XCTAssertEqual(MemoryLayout<OmniBorderPresentationInput>.size, 128)
        XCTAssertEqual(MemoryLayout<OmniBorderPresentationInput>.alignment, 8)
        assertOffset(OmniBorderPresentationInput.self, \.defer_updates, equals: 108)
        assertOffset(OmniBorderPresentationInput.self, \.update_mode, equals: 109)
        assertOffset(OmniBorderPresentationInput.self, \.layout_animation_active, equals: 110)
        assertOffset(OmniBorderPresentationInput.self, \.displays, equals: 112)
        assertOffset(OmniBorderPresentationInput.self, \.display_count, equals: 120)

        XCTAssertEqual(MemoryLayout<OmniBorderSnapshotInput>.size, 128)
        XCTAssertEqual(MemoryLayout<OmniBorderSnapshotInput>.alignment, 8)
        assertOffset(OmniBorderSnapshotInput.self, \.defer_updates, equals: 108)
        assertOffset(OmniBorderSnapshotInput.self, \.update_mode, equals: 109)
        assertOffset(OmniBorderSnapshotInput.self, \.layout_animation_active, equals: 110)
        assertOffset(OmniBorderSnapshotInput.self, \.force_hide, equals: 111)
        assertOffset(OmniBorderSnapshotInput.self, \.displays, equals: 112)
        assertOffset(OmniBorderSnapshotInput.self, \.display_count, equals: 120)
    }

    private func assertOffset<T, U>(
        _: T.Type,
        _ keyPath: KeyPath<T, U>,
        equals expected: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let offset = MemoryLayout<T>.offset(of: keyPath) else {
            XCTFail("Expected offset for \\(keyPath)", file: file, line: line)
            return
        }
        XCTAssertEqual(offset, expected, file: file, line: line)
    }
}

@MainActor
final class WMControllerBorderRuntimeResilienceTests: XCTestCase {
    func testControllerRecoversRuntimeWithoutClearingBorderPreference() {
        let suiteName = "WMControllerBorderRuntimeResilienceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected isolated defaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        settings.bordersEnabled = true

        var attempts = 0
        let controller = WMController(settings: settings, createBorderRuntime: {
            attempts += 1
            if attempts == 1 {
                return nil
            }
            return omni_border_runtime_create()
        })
        XCTAssertNil(controller.borderRuntime)
        XCTAssertFalse(controller.borderRuntimeDegraded)

        controller.syncBorderConfigFromSettings()

        XCTAssertNil(controller.borderRuntime)
        XCTAssertTrue(controller.borderRuntimeDegraded)
        XCTAssertTrue(settings.bordersEnabled)

        controller.resetBorderRuntimeHealth()
        controller.syncBorderConfigFromSettings()

        XCTAssertNotNil(controller.borderRuntime)
        XCTAssertFalse(controller.borderRuntimeDegraded)
        XCTAssertTrue(settings.bordersEnabled)
    }
}
