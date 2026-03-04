import CZigLayout
import CoreGraphics
import Foundation

enum DwindleZigKernel {
    enum NodeKind: UInt8 {
        case split = 0
        case leaf = 1
    }

    enum Orientation: UInt8 {
        case horizontal = 0
        case vertical = 1
    }

    struct SeedNode {
        let nodeId: UUID
        let parentIndex: Int
        let firstChildIndex: Int
        let secondChildIndex: Int
        let kind: NodeKind
        let orientation: Orientation
        let ratio: CGFloat
        let windowId: UUID?
        let isFullscreen: Bool
    }

    struct SeedState {
        let rootNodeIndex: Int
        let selectedNodeIndex: Int
        let preselection: Direction?

        init(
            rootNodeIndex: Int,
            selectedNodeIndex: Int = -1,
            preselection: Direction? = nil
        ) {
            self.rootNodeIndex = rootNodeIndex
            self.selectedNodeIndex = selectedNodeIndex
            self.preselection = preselection
        }
    }

    struct LayoutRequest {
        let screen: CGRect
        let innerGap: CGFloat
        let outerGapTop: CGFloat
        let outerGapBottom: CGFloat
        let outerGapLeft: CGFloat
        let outerGapRight: CGFloat
        let singleWindowAspectRatio: CGSize
        let singleWindowAspectTolerance: CGFloat

        init(screen: CGRect, settings: DwindleSettings) {
            self.screen = screen
            innerGap = settings.innerGap
            outerGapTop = settings.outerGapTop
            outerGapBottom = settings.outerGapBottom
            outerGapLeft = settings.outerGapLeft
            outerGapRight = settings.outerGapRight
            singleWindowAspectRatio = settings.singleWindowAspectRatio
            singleWindowAspectTolerance = settings.singleWindowAspectRatioTolerance
        }
    }

    struct WindowConstraint {
        let windowId: UUID
        let minSize: CGSize
        let maxSize: CGSize
        let hasMaxWidth: Bool
        let hasMaxHeight: Bool
        let isFixed: Bool

        init(windowId: UUID, constraints: WindowSizeConstraints) {
            self.windowId = windowId
            minSize = constraints.minSize
            maxSize = constraints.maxSize
            hasMaxWidth = constraints.hasMaxWidth
            hasMaxHeight = constraints.hasMaxHeight
            isFixed = constraints.isFixed
        }
    }

    struct LayoutResult {
        let rc: Int32
        let frameCount: Int
        let framesByWindowId: [UUID: CGRect]
    }

    struct NeighborResult {
        let rc: Int32
        let neighborWindowId: UUID?
    }

    final class LayoutContext {
        fileprivate let raw: OpaquePointer

        init?() {
            guard let raw = omni_dwindle_layout_context_create() else { return nil }
            self.raw = raw
        }

        deinit {
            omni_dwindle_layout_context_destroy(raw)
        }
    }

    static func seedState(
        context: LayoutContext,
        nodes: [SeedNode],
        state: SeedState
    ) -> Int32 {
        let rawNodes = nodes.map { node in
            OmniDwindleSeedNode(
                node_id: omniUUID(from: node.nodeId),
                parent_index: Int64(node.parentIndex),
                first_child_index: Int64(node.firstChildIndex),
                second_child_index: Int64(node.secondChildIndex),
                kind: node.kind.rawValue,
                orientation: node.orientation.rawValue,
                ratio: Double(node.ratio),
                has_window_id: node.windowId == nil ? 0 : 1,
                window_id: node.windowId.map(omniUUID(from:)) ?? zeroUUID(),
                is_fullscreen: node.isFullscreen ? 1 : 0
            )
        }

        var rawState = OmniDwindleSeedState(
            root_node_index: Int64(state.rootNodeIndex),
            selected_node_index: Int64(state.selectedNodeIndex),
            has_preselection: state.preselection == nil ? 0 : 1,
            preselection_direction: directionCode(state.preselection ?? .left)
        )

        return rawNodes.withUnsafeBufferPointer { nodeBuf in
            withUnsafePointer(to: &rawState) { statePtr in
                omni_dwindle_ctx_seed_state(
                    context.raw,
                    nodeBuf.baseAddress,
                    nodeBuf.count,
                    statePtr
                )
            }
        }
    }

    static func calculateLayout(
        context: LayoutContext,
        request: LayoutRequest,
        constraints: [WindowConstraint]
    ) -> LayoutResult {
        let rawRequest = OmniDwindleLayoutRequest(
            screen_x: Double(request.screen.minX),
            screen_y: Double(request.screen.minY),
            screen_width: Double(request.screen.width),
            screen_height: Double(request.screen.height),
            inner_gap: Double(request.innerGap),
            outer_gap_top: Double(request.outerGapTop),
            outer_gap_bottom: Double(request.outerGapBottom),
            outer_gap_left: Double(request.outerGapLeft),
            outer_gap_right: Double(request.outerGapRight),
            single_window_aspect_width: Double(request.singleWindowAspectRatio.width),
            single_window_aspect_height: Double(request.singleWindowAspectRatio.height),
            single_window_aspect_tolerance: Double(request.singleWindowAspectTolerance)
        )

        let rawConstraints = constraints.map { constraint in
            OmniDwindleWindowConstraint(
                window_id: omniUUID(from: constraint.windowId),
                min_width: Double(constraint.minSize.width),
                min_height: Double(constraint.minSize.height),
                max_width: Double(constraint.maxSize.width),
                max_height: Double(constraint.maxSize.height),
                has_max_width: constraint.hasMaxWidth ? 1 : 0,
                has_max_height: constraint.hasMaxHeight ? 1 : 0,
                is_fixed: constraint.isFixed ? 1 : 0
            )
        }

        var rawFrames = [OmniDwindleWindowFrame](
            repeating: OmniDwindleWindowFrame(
                window_id: zeroUUID(),
                frame_x: 0,
                frame_y: 0,
                frame_width: 0,
                frame_height: 0
            ),
            count: 512
        )

        var outFrameCount: Int = 0
        let rc: Int32 = rawConstraints.withUnsafeBufferPointer { constraintBuf in
            rawFrames.withUnsafeMutableBufferPointer { frameBuf in
                var mutableRequest = rawRequest
                return withUnsafePointer(to: &mutableRequest) { requestPtr in
                    withUnsafeMutablePointer(to: &outFrameCount) { outCountPtr in
                        omni_dwindle_ctx_calculate_layout(
                            context.raw,
                            requestPtr,
                            constraintBuf.baseAddress,
                            constraintBuf.count,
                            frameBuf.baseAddress,
                            frameBuf.count,
                            outCountPtr
                        )
                    }
                }
            }
        }

        guard rc == OMNI_OK else {
            return LayoutResult(rc: rc, frameCount: max(0, outFrameCount), framesByWindowId: [:])
        }

        let resolvedCount = min(max(outFrameCount, 0), rawFrames.count)
        var framesByWindowId: [UUID: CGRect] = [:]
        framesByWindowId.reserveCapacity(resolvedCount)

        for idx in 0 ..< resolvedCount {
            let frame = rawFrames[idx]
            framesByWindowId[uuid(from: frame.window_id)] = CGRect(
                x: frame.frame_x,
                y: frame.frame_y,
                width: frame.frame_width,
                height: frame.frame_height
            )
        }

        return LayoutResult(rc: rc, frameCount: outFrameCount, framesByWindowId: framesByWindowId)
    }

    static func findNeighbor(
        context: LayoutContext,
        windowId: UUID,
        direction: Direction,
        innerGap: CGFloat
    ) -> NeighborResult {
        var hasNeighbor: UInt8 = 0
        var neighborId = zeroUUID()

        let rc = withUnsafeMutablePointer(to: &hasNeighbor) { hasNeighborPtr in
            withUnsafeMutablePointer(to: &neighborId) { neighborPtr in
                omni_dwindle_ctx_find_neighbor(
                    context.raw,
                    omniUUID(from: windowId),
                    directionCode(direction),
                    Double(innerGap),
                    hasNeighborPtr,
                    neighborPtr
                )
            }
        }

        guard rc == OMNI_OK else {
            return NeighborResult(rc: rc, neighborWindowId: nil)
        }

        guard hasNeighbor != 0, !isZeroUUID(neighborId) else {
            return NeighborResult(rc: rc, neighborWindowId: nil)
        }

        return NeighborResult(rc: rc, neighborWindowId: uuid(from: neighborId))
    }

    static func omniUUID(from uuid: UUID) -> OmniUuid128 {
        var rawUUID = uuid.uuid
        var encoded = OmniUuid128()
        withUnsafeBytes(of: &rawUUID) { src in
            withUnsafeMutableBytes(of: &encoded) { dst in
                dst.copyBytes(from: src)
            }
        }
        return encoded
    }

    static func uuid(from omniUuid: OmniUuid128) -> UUID {
        var decoded = UUID().uuid
        var value = omniUuid
        withUnsafeBytes(of: &value) { src in
            withUnsafeMutableBytes(of: &decoded) { dst in
                dst.copyBytes(from: src)
            }
        }
        return UUID(uuid: decoded)
    }

    private static func zeroUUID() -> OmniUuid128 {
        OmniUuid128()
    }

    private static func isZeroUUID(_ value: OmniUuid128) -> Bool {
        withUnsafeBytes(of: value) { raw in
            raw.allSatisfy { $0 == 0 }
        }
    }

    private static func directionCode(_ direction: Direction) -> UInt8 {
        switch direction {
        case .left:
            return 0
        case .right:
            return 1
        case .up:
            return 2
        case .down:
            return 3
        }
    }
}
