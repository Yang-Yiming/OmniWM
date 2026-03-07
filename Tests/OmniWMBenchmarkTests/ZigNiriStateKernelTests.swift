import CoreGraphics
import CZigLayout
import XCTest

@testable import OmniWM

@MainActor
final class ZigNiriStateKernelTests: XCTestCase {
    private static let overflowCount = 513

    #if DEBUG
    func testApplyMutationKeepsAppliedWhenDeltaExportFails() throws {
        let context = try XCTUnwrap(ZigNiriLayoutKernel.LayoutContext())
        let columnId = NodeId()
        let windowId = NodeId()

        let seedRC = ZigNiriStateKernel.seedRuntimeState(
            context: context,
            export: ZigNiriStateKernel.RuntimeStateExport(
                columns: [
                    .init(
                        columnId: columnId,
                        windowStart: 0,
                        windowCount: 1,
                        activeTileIdx: 0,
                        isTabbed: false,
                        sizeValue: 1.0
                    ),
                ],
                windows: [
                    .init(
                        windowId: windowId,
                        columnId: columnId,
                        columnIndex: 0,
                        sizeValue: 1.0
                    ),
                ]
            )
        )
        XCTAssertEqual(seedRC, Int32(OMNI_OK))

        ZigNiriStateKernel.debugForceDeltaExportFailure = true
        defer { ZigNiriStateKernel.debugForceDeltaExportFailure = false }

        let outcome = ZigNiriStateKernel.applyMutation(
            context: context,
            request: .init(
                request: ZigNiriStateKernel.MutationRequest(
                    op: .setColumnDisplay,
                    sourceColumnId: columnId,
                    customU8A: 1
                )
            ),
            sampleTime: 0
        )

        XCTAssertEqual(outcome.rc, Int32(OMNI_OK))
        XCTAssertTrue(outcome.applied)
        XCTAssertNil(outcome.delta)

        let snapshot = ZigNiriStateKernel.snapshotRuntimeState(context: context)
        XCTAssertEqual(snapshot.rc, Int32(OMNI_OK))
        XCTAssertEqual(snapshot.export.columns.first?.isTabbed, true)
    }
    #endif

    func testSeedRuntimeStateRejectsOversizedExport() throws {
        let context = try XCTUnwrap(ZigNiriLayoutKernel.LayoutContext())
        let columns = (0 ..< Self.overflowCount).map { _ in
            ZigNiriStateKernel.RuntimeColumnState(
                columnId: NodeId(),
                windowStart: 0,
                windowCount: 0,
                activeTileIdx: 0,
                isTabbed: false,
                sizeValue: 1.0
            )
        }

        let rc = ZigNiriStateKernel.seedRuntimeState(
            context: context,
            export: ZigNiriStateKernel.RuntimeStateExport(
                columns: columns,
                windows: []
            )
        )

        XCTAssertEqual(rc, Int32(OMNI_ERR_OUT_OF_RANGE))
    }

    func testRenderRuntimeRejectsOversizedRequest() throws {
        let context = try XCTUnwrap(ZigNiriLayoutKernel.LayoutContext())
        let columns = Array(repeating: makeColumnInput(), count: Self.overflowCount)
        let windows = Array(repeating: makeWindowInput(), count: Self.overflowCount)

        let render = ZigNiriStateKernel.renderRuntime(
            context: context,
            request: ZigNiriStateKernel.RuntimeRenderRequest(
                columns: columns,
                windows: windows,
                workingFrame: CGRect(x: 0, y: 0, width: 1200, height: 800),
                viewFrame: CGRect(x: 0, y: 0, width: 1200, height: 800),
                fullscreenFrame: CGRect(x: 0, y: 0, width: 1200, height: 800),
                primaryGap: 8,
                secondaryGap: 8,
                viewStart: 0,
                viewportSpan: 1200,
                workspaceOffset: 0,
                scale: 2,
                orientation: .horizontal,
                sampleTime: 0
            )
        )

        XCTAssertEqual(render.rc, Int32(OMNI_ERR_OUT_OF_RANGE))
        XCTAssertTrue(render.output.windows.isEmpty)
        XCTAssertTrue(render.output.columns.isEmpty)
        XCTAssertFalse(render.output.animationActive)
    }

    func testViewportCommandsRejectOversizedSpans() throws {
        let context = try XCTUnwrap(ZigNiriLayoutKernel.LayoutContext())
        let spans = Array(repeating: 100.0, count: Self.overflowCount)

        let update = ZigNiriStateKernel.updateViewportGesture(
            context: context,
            spans: spans,
            deltaPixels: 40,
            timestamp: 0,
            gap: 8,
            viewportSpan: 1200
        )
        XCTAssertEqual(update.rc, Int32(OMNI_ERR_OUT_OF_RANGE))
        XCTAssertNil(update.result)

        let end = ZigNiriStateKernel.endViewportGesture(
            context: context,
            request: ZigNiriStateKernel.RuntimeViewportGestureEndRequest(
                spans: spans,
                gap: 8,
                viewportSpan: 1200,
                centerMode: .never,
                alwaysCenterSingleColumn: false,
                sampleTime: 0,
                displayRefreshRate: 120,
                reduceMotion: false
            )
        )
        XCTAssertEqual(end.rc, Int32(OMNI_ERR_OUT_OF_RANGE))
        XCTAssertNil(end.resolvedColumnIndex)

        let transition = ZigNiriStateKernel.transitionViewportToColumn(
            context: context,
            request: ZigNiriStateKernel.RuntimeViewportTransitionRequest(
                spans: spans,
                requestedIndex: 0,
                gap: 8,
                viewportSpan: 1200,
                centerMode: .never,
                alwaysCenterSingleColumn: false,
                animate: true,
                scale: 2,
                sampleTime: 0,
                displayRefreshRate: 120,
                reduceMotion: false
            )
        )
        XCTAssertEqual(transition.rc, Int32(OMNI_ERR_OUT_OF_RANGE))
        XCTAssertNil(transition.resolvedColumnIndex)
    }

    private func makeWindowInput() -> OmniNiriWindowInput {
        OmniNiriWindowInput(
            weight: 1,
            min_constraint: 16,
            max_constraint: 0,
            has_max_constraint: 0,
            is_constraint_fixed: 0,
            has_fixed_value: 0,
            fixed_value: 0,
            sizing_mode: UInt8(truncatingIfNeeded: OMNI_NIRI_SIZING_NORMAL.rawValue),
            render_offset_x: 0,
            render_offset_y: 0
        )
    }

    private func makeColumnInput() -> OmniNiriColumnInput {
        OmniNiriColumnInput(
            span: 1,
            render_offset_x: 0,
            render_offset_y: 0,
            is_tabbed: 0,
            tab_indicator_width: 0,
            window_start: 0,
            window_count: 0
        )
    }
}
