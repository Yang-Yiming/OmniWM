import ApplicationServices
import XCTest

@testable import OmniWM

@MainActor
final class ZigNiriEngineTests: XCTestCase {
    func testSyncWindowsProjectsRuntimeViewAndFocus() throws {
        let workspace = WorkspaceDescriptor(name: "zig-niri-sync-runtime-view")
        let engine = ZigNiriEngine()
        let firstHandle = makeWindowHandle()
        let secondHandle = makeWindowHandle()

        let removed = engine.syncWindows(
            [firstHandle, secondHandle],
            in: workspace.id,
            selectedNodeId: nil,
            focusedHandle: secondHandle
        )

        XCTAssertTrue(removed.isEmpty)

        let view = try XCTUnwrap(engine.workspaceView(for: workspace.id))
        XCTAssertEqual(view.windowsById.count, 2)
        XCTAssertEqual(view.columns.count, 1)

        let firstId = try XCTUnwrap(engine.nodeId(for: firstHandle))
        let secondId = try XCTUnwrap(engine.nodeId(for: secondHandle))
        XCTAssertNotNil(view.windowsById[firstId])
        XCTAssertNotNil(view.windowsById[secondId])
        XCTAssertEqual(view.selection?.focusedWindowId, secondId)
        XCTAssertEqual(view.windowsById[secondId]?.isFocused, true)
    }

    func testColumnDisplayAndWindowHeightMutationsProjectFromRuntime() throws {
        let workspace = WorkspaceDescriptor(name: "zig-niri-runtime-mutations")
        let engine = ZigNiriEngine()
        let handle = makeWindowHandle()

        _ = engine.syncWindows(
            [handle],
            in: workspace.id,
            selectedNodeId: nil
        )

        let baselineView = try XCTUnwrap(engine.workspaceView(for: workspace.id))
        let columnId = try XCTUnwrap(baselineView.columns.first?.nodeId)
        let windowId = try XCTUnwrap(engine.nodeId(for: handle))

        let displayResult = engine.applyMutation(
            .setColumnDisplay(columnId: columnId, display: .tabbed),
            in: workspace.id
        )
        XCTAssertTrue(displayResult.applied)

        let heightResult = engine.applyMutation(
            .setWindowHeight(windowId: windowId, height: .fixed(240)),
            in: workspace.id
        )
        XCTAssertTrue(heightResult.applied)

        let updatedView = try XCTUnwrap(engine.workspaceView(for: workspace.id))
        XCTAssertEqual(updatedView.columns.first?.display, .tabbed)

        guard case let .fixed(value)? = updatedView.windowsById[windowId]?.height else {
            XCTFail("Expected fixed height after runtime mutation projection")
            return
        }
        XCTAssertEqual(value, 240, accuracy: 0.001)
    }

    func testMoveWindowWorkspaceCommandProjectsBothWorkspaces() throws {
        let sourceWorkspace = WorkspaceDescriptor(name: "zig-niri-workspace-source")
        let targetWorkspace = WorkspaceDescriptor(name: "zig-niri-workspace-target")
        let engine = ZigNiriEngine()
        let handle = makeWindowHandle()

        _ = engine.syncWindows(
            [handle],
            in: sourceWorkspace.id,
            selectedNodeId: nil
        )
        let windowId = try XCTUnwrap(engine.nodeId(for: handle))

        let moveResult = engine.applyWorkspace(
            .moveWindow(windowId: windowId, targetWorkspaceId: targetWorkspace.id),
            in: sourceWorkspace.id
        )
        XCTAssertTrue(moveResult.applied)
        XCTAssertEqual(moveResult.workspaceId, targetWorkspace.id)

        let sourceView = try XCTUnwrap(engine.workspaceView(for: sourceWorkspace.id))
        let targetView = try XCTUnwrap(engine.workspaceView(for: targetWorkspace.id))
        XCTAssertNil(sourceView.windowsById[windowId])
        XCTAssertNotNil(targetView.windowsById[windowId])
        XCTAssertTrue(engine.windowHandle(for: windowId) === handle)
    }

    func testNavigationFocusWindowUsesRuntimeSelectionAnchor() throws {
        let workspace = WorkspaceDescriptor(name: "zig-niri-navigation-focus-window")
        let engine = ZigNiriEngine()
        let firstHandle = makeWindowHandle()
        let secondHandle = makeWindowHandle()

        _ = engine.syncWindows(
            [firstHandle, secondHandle],
            in: workspace.id,
            selectedNodeId: nil
        )

        let initialView = try XCTUnwrap(engine.workspaceView(for: workspace.id))
        let windowIds = try XCTUnwrap(initialView.columns.first?.windowIds)
        XCTAssertGreaterThanOrEqual(windowIds.count, 2)

        _ = engine.applyWorkspace(
            .setSelection(
                ZigNiriSelection(
                    selectedNodeId: windowIds[1],
                    focusedWindowId: windowIds[1]
                )
            ),
            in: workspace.id
        )

        let navResult = engine.applyNavigation(
            .focusWindow(index: 1),
            in: workspace.id
        )

        XCTAssertTrue(navResult.applied)
        XCTAssertEqual(navResult.targetNodeId, windowIds[1])
        XCTAssertEqual(navResult.selection?.selectedNodeId, windowIds[1])
    }

    private func makeWindowHandle() -> WindowHandle {
        let pid = getpid()
        return WindowHandle(
            id: UUID(),
            pid: pid,
            axElement: AXUIElementCreateApplication(pid)
        )
    }
}
