import CZigLayout
import XCTest

@testable import OmniWM

@MainActor
final class NiriRuntimeSeedTests: XCTestCase {
    func testEnsureLayoutContextBootstrapsRuntimeWithEmptyColumn() throws {
        let workspace = WorkspaceDescriptor(name: "seed-context-bootstrap-empty-column")
        let engine = NiriLayoutEngine()
        let root = engine.ensureRoot(for: workspace.id)
        let expectedColumnId = try XCTUnwrap(root.columns.first?.id)

        let context = try XCTUnwrap(engine.ensureLayoutContext(for: workspace.id))
        let export: NiriStateZigKernel.RuntimeStateExport
        switch NiriStateZigKernel.snapshotRuntimeStateResult(context: context) {
        case let .success(snapshot):
            export = snapshot
        case let .failure(error):
            XCTFail("Expected runtime snapshot after context bootstrap, got \(error)")
            return
        }

        XCTAssertEqual(export.columns.count, 1)
        XCTAssertEqual(export.windows.count, 0)
        XCTAssertEqual(export.columns.first?.columnId, expectedColumnId)
        XCTAssertEqual(export.columns.first?.windowStart, 0)
        XCTAssertEqual(export.columns.first?.windowCount, 0)
        XCTAssertEqual(export.columns.first?.activeTileIdx, 0)
        XCTAssertEqual(export.columns.first?.sizeValue, 1.0)
    }

    func testSeedRuntimeStateAcceptsWorkspaceWithEmptyColumn() throws {
        let workspace = WorkspaceDescriptor(name: "seed-empty")
        let engine = NiriLayoutEngine()
        _ = engine.ensureRoot(for: workspace.id)

        let snapshot = NiriStateZigKernel.makeSnapshot(columns: engine.columns(in: workspace.id))
        XCTAssertEqual(snapshot.columns.count, 1)
        XCTAssertEqual(snapshot.windows.count, 0)

        let context = try XCTUnwrap(engine.ensureLayoutContext(for: workspace.id))
        let rc = NiriStateZigKernel.seedRuntimeState(
            context: context,
            snapshot: snapshot
        )

        XCTAssertEqual(rc, Int32(OMNI_OK))
    }

    func testSeedRuntimeStateAcceptsCompletelyEmptyExport() throws {
        let context = try XCTUnwrap(NiriLayoutZigKernel.LayoutContext())
        let emptyExport = NiriStateZigKernel.RuntimeStateExport(columns: [], windows: [])

        let rc = NiriStateZigKernel.seedRuntimeState(
            context: context,
            export: emptyExport
        )

        XCTAssertEqual(rc, Int32(OMNI_OK))
    }
}
