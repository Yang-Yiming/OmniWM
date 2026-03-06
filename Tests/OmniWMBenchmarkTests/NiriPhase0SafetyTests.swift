import ApplicationServices
import CZigLayout
import XCTest

@testable import OmniWM

@MainActor
final class NiriPhase0SafetyTests: XCTestCase {
    private func makeWindow() -> NiriWindow {
        let pid = getpid()
        let handle = WindowHandle(
            id: UUID(),
            pid: pid,
            axElement: AXUIElementCreateApplication(pid)
        )
        return NiriWindow(handle: handle)
    }

    func testRuntimeStateDecodeRejectsMissingColumnsBuffer() {
        let raw = OmniNiriRuntimeStateExport(
            columns: nil,
            column_count: 1,
            windows: nil,
            window_count: 0
        )

        let result = NiriStateZigKernel.validateAndDecodeRuntimeStateExport(raw)
        switch result {
        case .success:
            XCTFail("Expected decode failure for nil columns pointer with non-zero count")
        case let .failure(error):
            XCTAssertEqual(error, .missingBuffer(field: "columns", count: 1))
            XCTAssertEqual(error.rc, Int32(OMNI_ERR_INVALID_ARGS))
        }
    }

    func testDeltaDecodeRejectsOversizedColumnCount() {
        var raw = OmniNiriTxnDeltaExport()
        raw.column_count = 513

        let result = NiriStateZigKernel.validateAndDecodeDeltaExport(raw)
        switch result {
        case .success:
            XCTFail("Expected decode failure for oversized delta column count")
        case let .failure(error):
            guard case let .countOutOfRange(field, count, max) = error else {
                XCTFail("Expected countOutOfRange error, got \(error)")
                return
            }
            XCTAssertEqual(field, "delta_column_count")
            XCTAssertEqual(count, 513)
            XCTAssertEqual(max, 512)
            XCTAssertEqual(error.rc, Int32(OMNI_ERR_OUT_OF_RANGE))
        }
    }

    func testRuntimeMirrorRejectsMissingWindowHandleWithoutMutation() throws {
        let workspace = WorkspaceDescriptor(name: "phase0-runtime-mirror-atomic")
        let engine = NiriLayoutEngine()
        let root = engine.ensureRoot(for: workspace.id)
        let sourceColumn = try XCTUnwrap(root.columns.first)

        let existingWindow = makeWindow()
        sourceColumn.appendChild(existingWindow)
        engine.handleToNode[existingWindow.handle] = existingWindow

        let before = NiriStateZigKernel.runtimeStateExport(
            snapshot: NiriStateZigKernel.makeSnapshot(columns: root.columns)
        )

        let runtimeColumnId = NodeId(uuid: UUID())
        let runtimeWindowId = NodeId(uuid: UUID())
        let context = try XCTUnwrap(engine.ensureLayoutContext(for: workspace.id))
        let seedRC = NiriStateZigKernel.seedRuntimeState(
            context: context,
            export: .init(
                columns: [
                    .init(
                        columnId: runtimeColumnId,
                        windowStart: 0,
                        windowCount: 1,
                        activeTileIdx: 0,
                        isTabbed: false,
                        sizeValue: 1.0
                    ),
                ],
                windows: [
                    .init(
                        windowId: runtimeWindowId,
                        columnId: runtimeColumnId,
                        columnIndex: 0,
                        sizeValue: 1.0
                    ),
                ]
            )
        )
        XCTAssertEqual(seedRC, Int32(OMNI_OK))

        let syncResult = engine.syncRuntimeWorkspaceMirror(
            workspaceId: workspace.id,
            ensureWorkspaceRoot: true
        )
        guard case let .failure(error) = syncResult else {
            XCTFail("Expected runtime mirror sync failure for missing window handle")
            return
        }
        guard case let .missingWindowHandle(resolvedWorkspaceId, resolvedWindowId) = error else {
            XCTFail("Expected missingWindowHandle error, got \(error)")
            return
        }
        XCTAssertEqual(resolvedWorkspaceId, workspace.id)
        XCTAssertEqual(resolvedWindowId, runtimeWindowId)

        let after = NiriStateZigKernel.runtimeStateExport(
            snapshot: NiriStateZigKernel.makeSnapshot(columns: root.columns)
        )
        XCTAssertEqual(after, before)
    }

    func testRuntimeMirrorAppliesSeededRuntimeStateToSwiftMirror() throws {
        let workspace = WorkspaceDescriptor(name: "phase0-runtime-mirror-apply")
        let engine = NiriLayoutEngine()
        let root = engine.ensureRoot(for: workspace.id)
        let sourceColumn = try XCTUnwrap(root.columns.first)

        let existingWindow = makeWindow()
        sourceColumn.appendChild(existingWindow)
        engine.handleToNode[existingWindow.handle] = existingWindow

        let runtimeColumnId = NodeId(uuid: UUID())
        let context = try XCTUnwrap(engine.ensureLayoutContext(for: workspace.id))
        let seedRC = NiriStateZigKernel.seedRuntimeState(
            context: context,
            export: .init(
                columns: [
                    .init(
                        columnId: runtimeColumnId,
                        windowStart: 0,
                        windowCount: 1,
                        activeTileIdx: 0,
                        isTabbed: true,
                        sizeValue: 420,
                        widthKind: NiriStateZigKernel.sizeKindFixed
                    ),
                ],
                windows: [
                    .init(
                        windowId: existingWindow.id,
                        columnId: runtimeColumnId,
                        columnIndex: 0,
                        sizeValue: 1.0,
                        heightKind: NiriStateZigKernel.heightKindAuto,
                        heightValue: 2.5
                    ),
                ]
            )
        )
        XCTAssertEqual(seedRC, Int32(OMNI_OK))

        switch engine.syncRuntimeWorkspaceMirror(workspaceId: workspace.id) {
        case .failure(let error):
            XCTFail("Expected runtime mirror sync success, got \(error)")
        case .success:
            break
        }

        let syncedColumn = try XCTUnwrap(engine.root(for: workspace.id)?.columns.first)
        XCTAssertEqual(syncedColumn.id, runtimeColumnId)
        XCTAssertTrue(syncedColumn.isTabbed)
        XCTAssertEqual(syncedColumn.width, .fixed(420))

        let syncedWindow = try XCTUnwrap(syncedColumn.windowNodes.first)
        XCTAssertEqual(syncedWindow.id, existingWindow.id)
        XCTAssertEqual(syncedWindow.height, .auto(weight: 2.5))
        XCTAssertEqual(engine.handleToNode[existingWindow.handle]?.id, existingWindow.id)
    }
}
