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

    func testProjectionRejectsInvalidColumnWidthWithoutMutation() throws {
        let workspace = WorkspaceDescriptor(name: "phase0-projection-atomic")
        let engine = NiriLayoutEngine()
        let root = engine.ensureRoot(for: workspace.id)
        let sourceColumn = try XCTUnwrap(root.columns.first)

        let firstWindow = makeWindow()
        let secondWindow = makeWindow()
        sourceColumn.appendChild(firstWindow)
        sourceColumn.appendChild(secondWindow)

        let before = NiriStateZigKernel.runtimeStateExport(
            snapshot: NiriStateZigKernel.makeSnapshot(columns: root.columns)
        )

        let secondColumnId = NodeId(uuid: UUID())
        let malformed = NiriStateZigKernel.RuntimeStateExport(
            columns: [
                .init(
                    columnId: sourceColumn.id,
                    windowStart: 0,
                    windowCount: 1,
                    activeTileIdx: 0,
                    isTabbed: false,
                    sizeValue: 1.0
                ),
                .init(
                    columnId: secondColumnId,
                    windowStart: 1,
                    windowCount: 1,
                    activeTileIdx: 0,
                    isTabbed: false,
                    sizeValue: 1.0,
                    widthKind: 0xFF
                ),
            ],
            windows: [
                .init(
                    windowId: firstWindow.id,
                    columnId: sourceColumn.id,
                    columnIndex: 0,
                    sizeValue: firstWindow.size
                ),
                .init(
                    windowId: secondWindow.id,
                    columnId: secondColumnId,
                    columnIndex: 1,
                    sizeValue: secondWindow.size
                ),
            ]
        )

        let projection = NiriStateZigRuntimeSnapshotApplier.project(
            export: malformed,
            workspaceId: workspace.id,
            engine: engine
        )

        XCTAssertFalse(projection.applied)
        guard case let .invalidRuntimeColumnWidth(columnId, _, _) = projection.error else {
            XCTFail("Expected invalidRuntimeColumnWidth error, got \(String(describing: projection.error))")
            return
        }
        XCTAssertEqual(columnId, secondColumnId)

        let after = NiriStateZigKernel.runtimeStateExport(
            snapshot: NiriStateZigKernel.makeSnapshot(columns: root.columns)
        )
        XCTAssertEqual(after, before)
    }

    func testWorkspaceProjectionSetIsAtomicWhenTargetProjectionFails() throws {
        let sourceWorkspace = WorkspaceDescriptor(name: "phase0-workspace-atomic-source")
        let targetWorkspace = WorkspaceDescriptor(name: "phase0-workspace-atomic-target")
        let engine = NiriLayoutEngine()

        let sourceRoot = engine.ensureRoot(for: sourceWorkspace.id)
        let targetRoot = engine.ensureRoot(for: targetWorkspace.id)
        let sourceColumn = try XCTUnwrap(sourceRoot.columns.first)
        let targetColumn = try XCTUnwrap(targetRoot.columns.first)

        let sourceWindow = makeWindow()
        let targetWindow = makeWindow()
        sourceColumn.appendChild(sourceWindow)
        targetColumn.appendChild(targetWindow)

        let sourceBefore = NiriStateZigKernel.runtimeStateExport(
            snapshot: NiriStateZigKernel.makeSnapshot(columns: sourceRoot.columns)
        )
        let targetBefore = NiriStateZigKernel.runtimeStateExport(
            snapshot: NiriStateZigKernel.makeSnapshot(columns: targetRoot.columns)
        )

        let sourceMutated = NiriStateZigKernel.RuntimeStateExport(
            columns: [
                .init(
                    columnId: sourceColumn.id,
                    windowStart: 0,
                    windowCount: 1,
                    activeTileIdx: 0,
                    isTabbed: true,
                    sizeValue: 480,
                    widthKind: NiriStateZigKernel.sizeKindFixed
                ),
            ],
            windows: [
                .init(
                    windowId: sourceWindow.id,
                    columnId: sourceColumn.id,
                    columnIndex: 0,
                    sizeValue: sourceWindow.size
                ),
            ]
        )

        let targetMalformed = NiriStateZigKernel.RuntimeStateExport(
            columns: [
                .init(
                    columnId: targetColumn.id,
                    windowStart: 0,
                    windowCount: 1,
                    activeTileIdx: 0,
                    isTabbed: false,
                    sizeValue: 1.0,
                    widthKind: 0xFF
                ),
            ],
            windows: [
                .init(
                    windowId: targetWindow.id,
                    columnId: targetColumn.id,
                    columnIndex: 0,
                    sizeValue: targetWindow.size
                ),
            ]
        )

        let result = NiriStateZigRuntimeSnapshotApplier.projectWorkspaceSet(
            sourceExport: sourceMutated,
            sourceWorkspaceId: sourceWorkspace.id,
            targetExport: targetMalformed,
            targetWorkspaceId: targetWorkspace.id,
            engine: engine
        )

        XCTAssertFalse(result.applied)
        guard case let .target(error) = result.error else {
            XCTFail("Expected target projection error, got \(String(describing: result.error))")
            return
        }
        guard case .invalidRuntimeColumnWidth = error else {
            XCTFail("Expected invalidRuntimeColumnWidth target error, got \(error)")
            return
        }

        let sourceAfter = NiriStateZigKernel.runtimeStateExport(
            snapshot: NiriStateZigKernel.makeSnapshot(columns: sourceRoot.columns)
        )
        let targetAfter = NiriStateZigKernel.runtimeStateExport(
            snapshot: NiriStateZigKernel.makeSnapshot(columns: targetRoot.columns)
        )

        XCTAssertEqual(sourceAfter, sourceBefore)
        XCTAssertEqual(targetAfter, targetBefore)
    }
}
