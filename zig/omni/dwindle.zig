const std = @import("std");
const abi = @import("abi_types.zig");

const MIN_RATIO: f64 = 0.1;
const MAX_RATIO: f64 = 1.9;
const MIN_FRACTION: f64 = 0.05;
const MAX_FRACTION: f64 = 0.95;
const STICKS_TOLERANCE: f64 = 2.0;
const NEIGHBOR_EDGE_THRESHOLD_EXTRA: f64 = 5.0;
const NEIGHBOR_MIN_OVERLAP_RATIO: f64 = 0.1;

const Rect = struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
};

const Size = struct {
    width: f64,
    height: f64,
};

const LayoutScratch = struct {
    frame_count: usize,
    frames: [abi.MAX_WINDOWS]abi.OmniDwindleWindowFrame,
    has_min_size: [abi.OMNI_DWINDLE_MAX_NODES]u8,
    min_sizes: [abi.OMNI_DWINDLE_MAX_NODES]Size,
};

pub const OmniDwindleLayoutContext = extern struct {
    node_count: usize,
    nodes: [abi.OMNI_DWINDLE_MAX_NODES]abi.OmniDwindleSeedNode,
    seed_state: abi.OmniDwindleSeedState,
    cached_frame_count: usize,
    cached_frames: [abi.MAX_WINDOWS]abi.OmniDwindleWindowFrame,
};

fn zeroUuid() abi.OmniUuid128 {
    return .{ .bytes = [_]u8{0} ** 16 };
}

fn isZeroUuid(uuid: abi.OmniUuid128) bool {
    return std.mem.eql(u8, uuid.bytes[0..], zeroUuid().bytes[0..]);
}

fn uuidEqual(a: abi.OmniUuid128, b: abi.OmniUuid128) bool {
    return std.mem.eql(u8, a.bytes[0..], b.bytes[0..]);
}

fn isFlag(value: u8) bool {
    return value == 0 or value == 1;
}

fn isFiniteNonNegative(value: f64) bool {
    return std.math.isFinite(value) and value >= 0;
}

fn rectMinX(rect: Rect) f64 {
    return rect.x;
}

fn rectMaxX(rect: Rect) f64 {
    return rect.x + rect.width;
}

fn rectMinY(rect: Rect) f64 {
    return rect.y;
}

fn rectMaxY(rect: Rect) f64 {
    return rect.y + rect.height;
}

fn rectToFrame(window_id: abi.OmniUuid128, rect: Rect) abi.OmniDwindleWindowFrame {
    return .{
        .window_id = window_id,
        .frame_x = rect.x,
        .frame_y = rect.y,
        .frame_width = rect.width,
        .frame_height = rect.height,
    };
}

fn frameToRect(frame: abi.OmniDwindleWindowFrame) Rect {
    return .{
        .x = frame.frame_x,
        .y = frame.frame_y,
        .width = frame.frame_width,
        .height = frame.frame_height,
    };
}

fn ratioToFraction(ratio: f64) f64 {
    const clamped_ratio = @min(@max(ratio, MIN_RATIO), MAX_RATIO);
    return @min(@max(clamped_ratio / 2.0, MIN_FRACTION), MAX_FRACTION);
}

fn applyOuterGapsOnly(rect: Rect, req: abi.OmniDwindleLayoutRequest) Rect {
    return .{
        .x = rect.x + req.outer_gap_left,
        .y = rect.y + req.outer_gap_bottom,
        .width = @max(1.0, rect.width - req.outer_gap_left - req.outer_gap_right),
        .height = @max(1.0, rect.height - req.outer_gap_top - req.outer_gap_bottom),
    };
}

fn applyGaps(node_rect: Rect, tiling_area: Rect, req: abi.OmniDwindleLayoutRequest) Rect {
    const at_left = @abs(rectMinX(node_rect) - rectMinX(tiling_area)) < STICKS_TOLERANCE;
    const at_right = @abs(rectMaxX(node_rect) - rectMaxX(tiling_area)) < STICKS_TOLERANCE;
    const at_bottom = @abs(rectMinY(node_rect) - rectMinY(tiling_area)) < STICKS_TOLERANCE;
    const at_top = @abs(rectMaxY(node_rect) - rectMaxY(tiling_area)) < STICKS_TOLERANCE;

    const left_gap = if (at_left) req.outer_gap_left else req.inner_gap / 2.0;
    const right_gap = if (at_right) req.outer_gap_right else req.inner_gap / 2.0;
    const bottom_gap = if (at_bottom) req.outer_gap_bottom else req.inner_gap / 2.0;
    const top_gap = if (at_top) req.outer_gap_top else req.inner_gap / 2.0;

    return .{
        .x = node_rect.x + left_gap,
        .y = node_rect.y + bottom_gap,
        .width = @max(1.0, node_rect.width - left_gap - right_gap),
        .height = @max(1.0, node_rect.height - top_gap - bottom_gap),
    };
}

fn singleWindowRect(screen: Rect, req: abi.OmniDwindleLayoutRequest) Rect {
    const target_ratio = if (@abs(req.single_window_aspect_height) < 0.001)
        std.math.inf(f64)
    else
        req.single_window_aspect_width / req.single_window_aspect_height;

    const current_ratio = if (@abs(screen.height) < 0.001)
        std.math.inf(f64)
    else
        screen.width / screen.height;

    if (@abs(target_ratio - current_ratio) < req.single_window_aspect_tolerance) {
        return screen;
    }

    var width = screen.width;
    var height = screen.height;

    if (current_ratio > target_ratio) {
        width = height * target_ratio;
    } else {
        height = width / target_ratio;
    }

    return .{
        .x = screen.x + (screen.width - width) / 2.0,
        .y = screen.y + (screen.height - height) / 2.0,
        .width = width,
        .height = height,
    };
}

fn splitRect(
    rect: Rect,
    orientation: u8,
    ratio: f64,
    first_min_size: Size,
    second_min_size: Size,
) [2]Rect {
    var fraction = ratioToFraction(ratio);

    switch (orientation) {
        abi.OMNI_DWINDLE_ORIENTATION_HORIZONTAL => {
            const total_min = first_min_size.width + second_min_size.width;
            if (total_min > rect.width) {
                const total_min_clamped = @max(total_min, 1.0);
                fraction = first_min_size.width / total_min_clamped;
            } else {
                const min_fraction = first_min_size.width / rect.width;
                const max_fraction = (rect.width - second_min_size.width) / rect.width;
                fraction = @max(min_fraction, @min(max_fraction, fraction));
            }

            const first_w = rect.width * fraction;
            const second_w = rect.width - first_w;
            return .{
                .{
                    .x = rect.x,
                    .y = rect.y,
                    .width = first_w,
                    .height = rect.height,
                },
                .{
                    .x = rect.x + first_w,
                    .y = rect.y,
                    .width = second_w,
                    .height = rect.height,
                },
            };
        },
        abi.OMNI_DWINDLE_ORIENTATION_VERTICAL => {
            const total_min = first_min_size.height + second_min_size.height;
            if (total_min > rect.height) {
                const total_min_clamped = @max(total_min, 1.0);
                fraction = first_min_size.height / total_min_clamped;
            } else {
                const min_fraction = first_min_size.height / rect.height;
                const max_fraction = (rect.height - second_min_size.height) / rect.height;
                fraction = @max(min_fraction, @min(max_fraction, fraction));
            }

            const first_h = rect.height * fraction;
            const second_h = rect.height - first_h;
            return .{
                .{
                    .x = rect.x,
                    .y = rect.y,
                    .width = rect.width,
                    .height = first_h,
                },
                .{
                    .x = rect.x,
                    .y = rect.y + first_h,
                    .width = rect.width,
                    .height = second_h,
                },
            };
        },
        else => unreachable,
    }
}

fn isValidDirection(direction: u8) bool {
    return switch (direction) {
        abi.OMNI_DWINDLE_DIRECTION_LEFT,
        abi.OMNI_DWINDLE_DIRECTION_RIGHT,
        abi.OMNI_DWINDLE_DIRECTION_UP,
        abi.OMNI_DWINDLE_DIRECTION_DOWN,
        => true,
        else => false,
    };
}

fn isValidOrientation(orientation: u8) bool {
    return switch (orientation) {
        abi.OMNI_DWINDLE_ORIENTATION_HORIZONTAL, abi.OMNI_DWINDLE_ORIENTATION_VERTICAL => true,
        else => false,
    };
}

fn isValidNodeKind(kind: u8) bool {
    return switch (kind) {
        abi.OMNI_DWINDLE_NODE_SPLIT, abi.OMNI_DWINDLE_NODE_LEAF => true,
        else => false,
    };
}

fn isValidOp(op: u8) bool {
    return switch (op) {
        abi.OMNI_DWINDLE_OP_ADD_WINDOW,
        abi.OMNI_DWINDLE_OP_REMOVE_WINDOW,
        abi.OMNI_DWINDLE_OP_SYNC_WINDOWS,
        abi.OMNI_DWINDLE_OP_MOVE_FOCUS,
        abi.OMNI_DWINDLE_OP_SWAP_WINDOWS,
        abi.OMNI_DWINDLE_OP_TOGGLE_FULLSCREEN,
        abi.OMNI_DWINDLE_OP_TOGGLE_ORIENTATION,
        abi.OMNI_DWINDLE_OP_RESIZE_SELECTED,
        abi.OMNI_DWINDLE_OP_BALANCE_SIZES,
        abi.OMNI_DWINDLE_OP_CYCLE_SPLIT_RATIO,
        abi.OMNI_DWINDLE_OP_MOVE_SELECTION_TO_ROOT,
        abi.OMNI_DWINDLE_OP_SWAP_SPLIT,
        abi.OMNI_DWINDLE_OP_SET_PRESELECTION,
        abi.OMNI_DWINDLE_OP_CLEAR_PRESELECTION,
        abi.OMNI_DWINDLE_OP_VALIDATE_SELECTION,
        => true,
        else => false,
    };
}

fn parseOptionalIndex(raw: i64, count: usize, out_index: *?usize) i32 {
    if (raw == -1) {
        out_index.* = null;
        return abi.OMNI_OK;
    }
    if (raw < -1) return abi.OMNI_ERR_OUT_OF_RANGE;
    const index = std.math.cast(usize, raw) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
    if (index >= count) return abi.OMNI_ERR_OUT_OF_RANGE;
    out_index.* = index;
    return abi.OMNI_OK;
}

fn resetContext(ctx: *OmniDwindleLayoutContext) void {
    ctx.node_count = 0;
    ctx.seed_state = .{
        .root_node_index = -1,
        .selected_node_index = -1,
        .has_preselection = 0,
        .preselection_direction = abi.OMNI_DWINDLE_DIRECTION_LEFT,
    };
    ctx.cached_frame_count = 0;
}

fn asMutableContext(context: [*c]OmniDwindleLayoutContext) ?*OmniDwindleLayoutContext {
    if (context == null) return null;
    const ptr: *OmniDwindleLayoutContext = @ptrCast(&context[0]);
    return ptr;
}

fn asConstContext(context: [*c]const OmniDwindleLayoutContext) ?*const OmniDwindleLayoutContext {
    if (context == null) return null;
    const ptr: *const OmniDwindleLayoutContext = @ptrCast(&context[0]);
    return ptr;
}

fn initOpResult(out_result: [*c]abi.OmniDwindleOpResult) void {
    out_result[0] = .{
        .applied = 0,
        .has_selected_window_id = 0,
        .selected_window_id = zeroUuid(),
        .has_focused_window_id = 0,
        .focused_window_id = zeroUuid(),
        .has_preselection = 0,
        .preselection_direction = abi.OMNI_DWINDLE_DIRECTION_LEFT,
        .removed_window_count = 0,
    };
}

fn validateNodeIdUniqueness(nodes: [*c]const abi.OmniDwindleSeedNode, node_count: usize) i32 {
    for (0..node_count) |idx| {
        const current = nodes[idx].node_id;
        for ((idx + 1)..node_count) |other_idx| {
            if (uuidEqual(current, nodes[other_idx].node_id)) {
                return abi.OMNI_ERR_INVALID_ARGS;
            }
        }
    }
    return abi.OMNI_OK;
}

fn validateWindowIdUniqueness(nodes: [*c]const abi.OmniDwindleSeedNode, node_count: usize) i32 {
    for (0..node_count) |idx| {
        if (nodes[idx].has_window_id == 0) continue;
        const current = nodes[idx].window_id;
        for ((idx + 1)..node_count) |other_idx| {
            if (nodes[other_idx].has_window_id == 0) continue;
            if (uuidEqual(current, nodes[other_idx].window_id)) {
                return abi.OMNI_ERR_INVALID_ARGS;
            }
        }
    }
    return abi.OMNI_OK;
}

fn validateAcyclicParentChain(nodes: [*c]const abi.OmniDwindleSeedNode, node_count: usize) i32 {
    for (0..node_count) |start_idx| {
        var current_idx = start_idx;
        var steps: usize = 0;

        while (true) {
            const parent_raw = nodes[current_idx].parent_index;
            if (parent_raw == -1) break;

            const parent = std.math.cast(usize, parent_raw) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            if (parent >= node_count) return abi.OMNI_ERR_OUT_OF_RANGE;

            steps += 1;
            if (steps > node_count) return abi.OMNI_ERR_INVALID_ARGS;
            current_idx = parent;
        }
    }

    return abi.OMNI_OK;
}

fn validateReachabilityFromRoot(
    nodes: [*c]const abi.OmniDwindleSeedNode,
    node_count: usize,
    root_idx: usize,
) i32 {
    var visited = [_]u8{0} ** abi.OMNI_DWINDLE_MAX_NODES;
    var stack = [_]usize{0} ** abi.OMNI_DWINDLE_MAX_NODES;
    var stack_len: usize = 0;
    var visited_count: usize = 0;

    stack[0] = root_idx;
    stack_len = 1;

    while (stack_len > 0) {
        stack_len -= 1;
        const node_index = stack[stack_len];
        if (node_index >= node_count) return abi.OMNI_ERR_OUT_OF_RANGE;

        if (visited[node_index] != 0) return abi.OMNI_ERR_INVALID_ARGS;
        visited[node_index] = 1;
        visited_count += 1;

        const node = nodes[node_index];
        if (node.kind == abi.OMNI_DWINDLE_NODE_SPLIT) {
            const first = std.math.cast(usize, node.first_child_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const second = std.math.cast(usize, node.second_child_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            if (first >= node_count or second >= node_count) return abi.OMNI_ERR_OUT_OF_RANGE;

            if (stack_len + 2 > node_count) return abi.OMNI_ERR_INVALID_ARGS;
            stack[stack_len] = first;
            stack_len += 1;
            stack[stack_len] = second;
            stack_len += 1;
        }
    }

    if (visited_count != node_count) return abi.OMNI_ERR_INVALID_ARGS;
    return abi.OMNI_OK;
}

fn validateConstraints(
    constraints: [*c]const abi.OmniDwindleWindowConstraint,
    constraint_count: usize,
) i32 {
    for (0..constraint_count) |idx| {
        const constraint = constraints[idx];
        if (isZeroUuid(constraint.window_id)) return abi.OMNI_ERR_INVALID_ARGS;
        if (!isFlag(constraint.has_max_width) or
            !isFlag(constraint.has_max_height) or
            !isFlag(constraint.is_fixed))
        {
            return abi.OMNI_ERR_INVALID_ARGS;
        }
        if (!isFiniteNonNegative(constraint.min_width) or
            !isFiniteNonNegative(constraint.min_height) or
            !isFiniteNonNegative(constraint.max_width) or
            !isFiniteNonNegative(constraint.max_height))
        {
            return abi.OMNI_ERR_INVALID_ARGS;
        }

        for ((idx + 1)..constraint_count) |other_idx| {
            if (uuidEqual(constraint.window_id, constraints[other_idx].window_id)) {
                return abi.OMNI_ERR_INVALID_ARGS;
            }
        }
    }
    return abi.OMNI_OK;
}

fn constraintMinSize(
    window_id: abi.OmniUuid128,
    constraints: [*c]const abi.OmniDwindleWindowConstraint,
    constraint_count: usize,
) Size {
    for (0..constraint_count) |idx| {
        const constraint = constraints[idx];
        if (!uuidEqual(constraint.window_id, window_id)) continue;
        return .{
            .width = constraint.min_width,
            .height = constraint.min_height,
        };
    }
    return .{
        .width = 1.0,
        .height = 1.0,
    };
}

fn appendFrame(
    scratch: *LayoutScratch,
    window_id: abi.OmniUuid128,
    rect: Rect,
) i32 {
    if (scratch.frame_count >= abi.MAX_WINDOWS) return abi.OMNI_ERR_OUT_OF_RANGE;
    scratch.frames[scratch.frame_count] = rectToFrame(window_id, rect);
    scratch.frame_count += 1;
    return abi.OMNI_OK;
}

fn countWindowLeaves(
    ctx: *const OmniDwindleLayoutContext,
    node_index: usize,
    out_count: *usize,
) i32 {
    if (node_index >= ctx.node_count) return abi.OMNI_ERR_OUT_OF_RANGE;
    const node = ctx.nodes[node_index];

    if (node.kind == abi.OMNI_DWINDLE_NODE_LEAF) {
        if (node.has_window_id != 0) out_count.* += 1;
        return abi.OMNI_OK;
    }

    if (node.kind != abi.OMNI_DWINDLE_NODE_SPLIT) return abi.OMNI_ERR_INVALID_ARGS;

    const first_idx = std.math.cast(usize, node.first_child_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
    const second_idx = std.math.cast(usize, node.second_child_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
    if (first_idx >= ctx.node_count or second_idx >= ctx.node_count) return abi.OMNI_ERR_OUT_OF_RANGE;

    var rc = countWindowLeaves(ctx, first_idx, out_count);
    if (rc != abi.OMNI_OK) return rc;
    rc = countWindowLeaves(ctx, second_idx, out_count);
    if (rc != abi.OMNI_OK) return rc;
    return abi.OMNI_OK;
}

fn findSingleWindowLeaf(
    ctx: *const OmniDwindleLayoutContext,
    node_index: usize,
) ?usize {
    if (node_index >= ctx.node_count) return null;
    const node = ctx.nodes[node_index];

    if (node.kind == abi.OMNI_DWINDLE_NODE_LEAF) {
        if (node.has_window_id != 0) return node_index;
        return null;
    }

    if (node.kind != abi.OMNI_DWINDLE_NODE_SPLIT) return null;

    const first_idx = std.math.cast(usize, node.first_child_index) orelse return null;
    const second_idx = std.math.cast(usize, node.second_child_index) orelse return null;
    if (first_idx >= ctx.node_count or second_idx >= ctx.node_count) return null;

    if (findSingleWindowLeaf(ctx, first_idx)) |candidate| {
        return candidate;
    }
    return findSingleWindowLeaf(ctx, second_idx);
}

fn computeMinSizeForSubtree(
    ctx: *const OmniDwindleLayoutContext,
    constraints: [*c]const abi.OmniDwindleWindowConstraint,
    constraint_count: usize,
    scratch: *LayoutScratch,
    node_index: usize,
    out_min_size: *Size,
) i32 {
    if (node_index >= ctx.node_count) return abi.OMNI_ERR_OUT_OF_RANGE;

    if (scratch.has_min_size[node_index] != 0) {
        out_min_size.* = scratch.min_sizes[node_index];
        return abi.OMNI_OK;
    }

    const node = ctx.nodes[node_index];
    var result = Size{ .width = 1.0, .height = 1.0 };

    switch (node.kind) {
        abi.OMNI_DWINDLE_NODE_LEAF => {
            if (node.has_window_id != 0) {
                result = constraintMinSize(node.window_id, constraints, constraint_count);
            }
        },
        abi.OMNI_DWINDLE_NODE_SPLIT => {
            const first_idx = std.math.cast(usize, node.first_child_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const second_idx = std.math.cast(usize, node.second_child_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            if (first_idx >= ctx.node_count or second_idx >= ctx.node_count) return abi.OMNI_ERR_OUT_OF_RANGE;

            var first_min = Size{ .width = 1.0, .height = 1.0 };
            var second_min = Size{ .width = 1.0, .height = 1.0 };

            var rc = computeMinSizeForSubtree(
                ctx,
                constraints,
                constraint_count,
                scratch,
                first_idx,
                &first_min,
            );
            if (rc != abi.OMNI_OK) return rc;

            rc = computeMinSizeForSubtree(
                ctx,
                constraints,
                constraint_count,
                scratch,
                second_idx,
                &second_min,
            );
            if (rc != abi.OMNI_OK) return rc;

            switch (node.orientation) {
                abi.OMNI_DWINDLE_ORIENTATION_HORIZONTAL => {
                    result = .{
                        .width = first_min.width + second_min.width,
                        .height = @max(first_min.height, second_min.height),
                    };
                },
                abi.OMNI_DWINDLE_ORIENTATION_VERTICAL => {
                    result = .{
                        .width = @max(first_min.width, second_min.width),
                        .height = first_min.height + second_min.height,
                    };
                },
                else => return abi.OMNI_ERR_INVALID_ARGS,
            }
        },
        else => return abi.OMNI_ERR_INVALID_ARGS,
    }

    scratch.min_sizes[node_index] = result;
    scratch.has_min_size[node_index] = 1;
    out_min_size.* = result;
    return abi.OMNI_OK;
}

fn layoutRecursive(
    ctx: *const OmniDwindleLayoutContext,
    constraints: [*c]const abi.OmniDwindleWindowConstraint,
    constraint_count: usize,
    req: abi.OmniDwindleLayoutRequest,
    scratch: *LayoutScratch,
    node_index: usize,
    rect: Rect,
    tiling_area: Rect,
) i32 {
    if (node_index >= ctx.node_count) return abi.OMNI_ERR_OUT_OF_RANGE;
    const node = ctx.nodes[node_index];

    switch (node.kind) {
        abi.OMNI_DWINDLE_NODE_LEAF => {
            if (node.has_window_id == 0) return abi.OMNI_OK;

            const target = if (node.is_fullscreen != 0)
                tiling_area
            else
                applyGaps(rect, tiling_area, req);
            return appendFrame(scratch, node.window_id, target);
        },
        abi.OMNI_DWINDLE_NODE_SPLIT => {
            const first_idx = std.math.cast(usize, node.first_child_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const second_idx = std.math.cast(usize, node.second_child_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            if (first_idx >= ctx.node_count or second_idx >= ctx.node_count) return abi.OMNI_ERR_OUT_OF_RANGE;

            var first_min = Size{ .width = 1.0, .height = 1.0 };
            var second_min = Size{ .width = 1.0, .height = 1.0 };

            var rc = computeMinSizeForSubtree(
                ctx,
                constraints,
                constraint_count,
                scratch,
                first_idx,
                &first_min,
            );
            if (rc != abi.OMNI_OK) return rc;

            rc = computeMinSizeForSubtree(
                ctx,
                constraints,
                constraint_count,
                scratch,
                second_idx,
                &second_min,
            );
            if (rc != abi.OMNI_OK) return rc;

            const split_rects = splitRect(
                rect,
                node.orientation,
                node.ratio,
                first_min,
                second_min,
            );

            rc = layoutRecursive(
                ctx,
                constraints,
                constraint_count,
                req,
                scratch,
                first_idx,
                split_rects[0],
                tiling_area,
            );
            if (rc != abi.OMNI_OK) return rc;

            rc = layoutRecursive(
                ctx,
                constraints,
                constraint_count,
                req,
                scratch,
                second_idx,
                split_rects[1],
                tiling_area,
            );
            if (rc != abi.OMNI_OK) return rc;
            return abi.OMNI_OK;
        },
        else => return abi.OMNI_ERR_INVALID_ARGS,
    }
}

fn calculateDirectionalOverlap(
    source: Rect,
    target: Rect,
    direction: u8,
    inner_gap: f64,
) ?f64 {
    const edge_threshold = inner_gap + NEIGHBOR_EDGE_THRESHOLD_EXTRA;
    const min_overlap_ratio = NEIGHBOR_MIN_OVERLAP_RATIO;

    switch (direction) {
        abi.OMNI_DWINDLE_DIRECTION_UP => {
            const edges_touch = @abs(rectMaxY(source) - rectMinY(target)) < edge_threshold;
            if (!edges_touch) return null;

            const overlap_start = @max(rectMinX(source), rectMinX(target));
            const overlap_end = @min(rectMaxX(source), rectMaxX(target));
            const overlap = @max(0.0, overlap_end - overlap_start);
            const min_required = @min(source.width, target.width) * min_overlap_ratio;
            return if (overlap >= min_required) overlap else null;
        },
        abi.OMNI_DWINDLE_DIRECTION_DOWN => {
            const edges_touch = @abs(rectMinY(source) - rectMaxY(target)) < edge_threshold;
            if (!edges_touch) return null;

            const overlap_start = @max(rectMinX(source), rectMinX(target));
            const overlap_end = @min(rectMaxX(source), rectMaxX(target));
            const overlap = @max(0.0, overlap_end - overlap_start);
            const min_required = @min(source.width, target.width) * min_overlap_ratio;
            return if (overlap >= min_required) overlap else null;
        },
        abi.OMNI_DWINDLE_DIRECTION_LEFT => {
            const edges_touch = @abs(rectMinX(source) - rectMaxX(target)) < edge_threshold;
            if (!edges_touch) return null;

            const overlap_start = @max(rectMinY(source), rectMinY(target));
            const overlap_end = @min(rectMaxY(source), rectMaxY(target));
            const overlap = @max(0.0, overlap_end - overlap_start);
            const min_required = @min(source.height, target.height) * min_overlap_ratio;
            return if (overlap >= min_required) overlap else null;
        },
        abi.OMNI_DWINDLE_DIRECTION_RIGHT => {
            const edges_touch = @abs(rectMaxX(source) - rectMinX(target)) < edge_threshold;
            if (!edges_touch) return null;

            const overlap_start = @max(rectMinY(source), rectMinY(target));
            const overlap_end = @min(rectMaxY(source), rectMaxY(target));
            const overlap = @max(0.0, overlap_end - overlap_start);
            const min_required = @min(source.height, target.height) * min_overlap_ratio;
            return if (overlap >= min_required) overlap else null;
        },
        else => return null,
    }
}

pub fn omni_dwindle_layout_context_create_impl() [*c]OmniDwindleLayoutContext {
    const ctx = std.heap.c_allocator.create(OmniDwindleLayoutContext) catch return null;
    ctx.* = undefined;
    resetContext(ctx);
    return @ptrCast(ctx);
}

pub fn omni_dwindle_layout_context_destroy_impl(context: [*c]OmniDwindleLayoutContext) void {
    const ctx = asMutableContext(context) orelse return;
    std.heap.c_allocator.destroy(ctx);
}

pub fn omni_dwindle_ctx_seed_state_impl(
    context: [*c]OmniDwindleLayoutContext,
    nodes: [*c]const abi.OmniDwindleSeedNode,
    node_count: usize,
    seed_state: [*c]const abi.OmniDwindleSeedState,
) i32 {
    const ctx = asMutableContext(context) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (seed_state == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (node_count > abi.OMNI_DWINDLE_MAX_NODES) return abi.OMNI_ERR_OUT_OF_RANGE;
    if (node_count > 0 and nodes == null) return abi.OMNI_ERR_INVALID_ARGS;

    if (!isFlag(seed_state[0].has_preselection)) return abi.OMNI_ERR_INVALID_ARGS;
    if (seed_state[0].has_preselection != 0 and !isValidDirection(seed_state[0].preselection_direction)) {
        return abi.OMNI_ERR_INVALID_ARGS;
    }

    if (node_count == 0) {
        if (seed_state[0].root_node_index != -1 or seed_state[0].selected_node_index != -1) {
            return abi.OMNI_ERR_OUT_OF_RANGE;
        }
        resetContext(ctx);
        ctx.seed_state = seed_state[0];
        return abi.OMNI_OK;
    }

    var root_idx: ?usize = null;
    var selected_idx: ?usize = null;
    var rc = parseOptionalIndex(seed_state[0].root_node_index, node_count, &root_idx);
    if (rc != abi.OMNI_OK) return rc;
    rc = parseOptionalIndex(seed_state[0].selected_node_index, node_count, &selected_idx);
    if (rc != abi.OMNI_OK) return rc;
    if (root_idx == null) return abi.OMNI_ERR_OUT_OF_RANGE;

    for (0..node_count) |idx| {
        const node = nodes[idx];
        if (!isValidNodeKind(node.kind)) return abi.OMNI_ERR_INVALID_ARGS;
        if (!isValidOrientation(node.orientation)) return abi.OMNI_ERR_INVALID_ARGS;
        if (!isFlag(node.has_window_id) or !isFlag(node.is_fullscreen)) return abi.OMNI_ERR_INVALID_ARGS;
        if (!std.math.isFinite(node.ratio)) return abi.OMNI_ERR_INVALID_ARGS;
        if (node.ratio < MIN_RATIO or node.ratio > MAX_RATIO) return abi.OMNI_ERR_OUT_OF_RANGE;

        var parent_idx: ?usize = null;
        var first_child_idx: ?usize = null;
        var second_child_idx: ?usize = null;

        rc = parseOptionalIndex(node.parent_index, node_count, &parent_idx);
        if (rc != abi.OMNI_OK) return rc;
        rc = parseOptionalIndex(node.first_child_index, node_count, &first_child_idx);
        if (rc != abi.OMNI_OK) return rc;
        rc = parseOptionalIndex(node.second_child_index, node_count, &second_child_idx);
        if (rc != abi.OMNI_OK) return rc;

        if (parent_idx != null and parent_idx.? == idx) return abi.OMNI_ERR_INVALID_ARGS;
        if (first_child_idx != null and first_child_idx.? == idx) return abi.OMNI_ERR_INVALID_ARGS;
        if (second_child_idx != null and second_child_idx.? == idx) return abi.OMNI_ERR_INVALID_ARGS;

        switch (node.kind) {
            abi.OMNI_DWINDLE_NODE_SPLIT => {
                if (first_child_idx == null or second_child_idx == null) return abi.OMNI_ERR_INVALID_ARGS;
                if (first_child_idx.? == second_child_idx.?) return abi.OMNI_ERR_INVALID_ARGS;
                if (node.has_window_id != 0 or node.is_fullscreen != 0) return abi.OMNI_ERR_INVALID_ARGS;
            },
            abi.OMNI_DWINDLE_NODE_LEAF => {
                if (first_child_idx != null or second_child_idx != null) return abi.OMNI_ERR_INVALID_ARGS;
                if (node.has_window_id == 0 and node.is_fullscreen != 0) return abi.OMNI_ERR_INVALID_ARGS;
            },
            else => return abi.OMNI_ERR_INVALID_ARGS,
        }
    }

    for (0..node_count) |idx| {
        const node = nodes[idx];
        var parent_idx: ?usize = null;
        rc = parseOptionalIndex(node.parent_index, node_count, &parent_idx);
        if (rc != abi.OMNI_OK) return rc;

        if (parent_idx) |parent| {
            const parent_node = nodes[parent];
            if (parent_node.kind != abi.OMNI_DWINDLE_NODE_SPLIT) return abi.OMNI_ERR_INVALID_ARGS;
            const idx_i64 = std.math.cast(i64, idx) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const matches_first = parent_node.first_child_index == idx_i64;
            const matches_second = parent_node.second_child_index == idx_i64;
            if (!matches_first and !matches_second) return abi.OMNI_ERR_INVALID_ARGS;
        }

        if (node.kind == abi.OMNI_DWINDLE_NODE_SPLIT) {
            const first = std.math.cast(usize, node.first_child_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const second = std.math.cast(usize, node.second_child_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            const idx_i64 = std.math.cast(i64, idx) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
            if (nodes[first].parent_index != idx_i64) {
                return abi.OMNI_ERR_INVALID_ARGS;
            }
            if (nodes[second].parent_index != idx_i64) {
                return abi.OMNI_ERR_INVALID_ARGS;
            }
        }
    }

    const root = root_idx.?;
    if (nodes[root].parent_index != -1) return abi.OMNI_ERR_INVALID_ARGS;

    rc = validateNodeIdUniqueness(nodes, node_count);
    if (rc != abi.OMNI_OK) return rc;
    rc = validateWindowIdUniqueness(nodes, node_count);
    if (rc != abi.OMNI_OK) return rc;
    rc = validateAcyclicParentChain(nodes, node_count);
    if (rc != abi.OMNI_OK) return rc;
    rc = validateReachabilityFromRoot(nodes, node_count, root);
    if (rc != abi.OMNI_OK) return rc;

    if (selected_idx) |selected| {
        if (selected >= node_count) return abi.OMNI_ERR_OUT_OF_RANGE;
    }

    ctx.node_count = node_count;
    for (0..node_count) |idx| {
        ctx.nodes[idx] = nodes[idx];
    }
    ctx.seed_state = seed_state[0];
    ctx.cached_frame_count = 0;

    return abi.OMNI_OK;
}

pub fn omni_dwindle_ctx_apply_op_impl(
    context: [*c]OmniDwindleLayoutContext,
    request: [*c]const abi.OmniDwindleOpRequest,
    out_result: [*c]abi.OmniDwindleOpResult,
    out_removed_window_ids: [*c]abi.OmniUuid128,
    out_removed_window_capacity: usize,
) i32 {
    _ = asMutableContext(context) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (request == null or out_result == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (out_removed_window_capacity > 0 and out_removed_window_ids == null) return abi.OMNI_ERR_INVALID_ARGS;

    initOpResult(out_result);

    const op = request[0].op;
    if (!isValidOp(op)) return abi.OMNI_ERR_INVALID_ARGS;

    switch (op) {
        abi.OMNI_DWINDLE_OP_ADD_WINDOW => {
            if (isZeroUuid(request[0].payload.add_window.window_id)) return abi.OMNI_ERR_INVALID_ARGS;
        },
        abi.OMNI_DWINDLE_OP_REMOVE_WINDOW => {
            if (isZeroUuid(request[0].payload.remove_window.window_id)) return abi.OMNI_ERR_INVALID_ARGS;
        },
        abi.OMNI_DWINDLE_OP_SYNC_WINDOWS => {
            const payload = request[0].payload.sync_windows;
            if (payload.window_count > abi.MAX_WINDOWS) return abi.OMNI_ERR_OUT_OF_RANGE;
            if (payload.window_count > 0 and payload.window_ids == null) return abi.OMNI_ERR_INVALID_ARGS;
        },
        abi.OMNI_DWINDLE_OP_MOVE_FOCUS => {
            if (!isValidDirection(request[0].payload.move_focus.direction)) return abi.OMNI_ERR_INVALID_ARGS;
        },
        abi.OMNI_DWINDLE_OP_SWAP_WINDOWS => {
            if (!isValidDirection(request[0].payload.swap_windows.direction)) return abi.OMNI_ERR_INVALID_ARGS;
        },
        abi.OMNI_DWINDLE_OP_RESIZE_SELECTED => {
            const payload = request[0].payload.resize_selected;
            if (!isValidDirection(payload.direction)) return abi.OMNI_ERR_INVALID_ARGS;
            if (!std.math.isFinite(payload.delta)) return abi.OMNI_ERR_INVALID_ARGS;
        },
        abi.OMNI_DWINDLE_OP_CYCLE_SPLIT_RATIO => {
            if (!isFlag(request[0].payload.cycle_split_ratio.forward)) return abi.OMNI_ERR_INVALID_ARGS;
        },
        abi.OMNI_DWINDLE_OP_MOVE_SELECTION_TO_ROOT => {
            if (!isFlag(request[0].payload.move_selection_to_root.stable)) return abi.OMNI_ERR_INVALID_ARGS;
        },
        abi.OMNI_DWINDLE_OP_SET_PRESELECTION => {
            if (!isValidDirection(request[0].payload.set_preselection.direction)) return abi.OMNI_ERR_INVALID_ARGS;
        },
        abi.OMNI_DWINDLE_OP_TOGGLE_FULLSCREEN,
        abi.OMNI_DWINDLE_OP_TOGGLE_ORIENTATION,
        abi.OMNI_DWINDLE_OP_BALANCE_SIZES,
        abi.OMNI_DWINDLE_OP_SWAP_SPLIT,
        abi.OMNI_DWINDLE_OP_CLEAR_PRESELECTION,
        abi.OMNI_DWINDLE_OP_VALIDATE_SELECTION,
        => {},
        else => return abi.OMNI_ERR_INVALID_ARGS,
    }

    return abi.OMNI_OK;
}

pub fn omni_dwindle_ctx_calculate_layout_impl(
    context: [*c]OmniDwindleLayoutContext,
    request: [*c]const abi.OmniDwindleLayoutRequest,
    constraints: [*c]const abi.OmniDwindleWindowConstraint,
    constraint_count: usize,
    out_frames: [*c]abi.OmniDwindleWindowFrame,
    out_frame_capacity: usize,
    out_frame_count: [*c]usize,
) i32 {
    const ctx = asMutableContext(context) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (request == null or out_frame_count == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (constraint_count > abi.MAX_WINDOWS) return abi.OMNI_ERR_OUT_OF_RANGE;
    if (constraint_count > 0 and constraints == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (out_frame_capacity > abi.MAX_WINDOWS) return abi.OMNI_ERR_OUT_OF_RANGE;
    if (out_frame_capacity > 0 and out_frames == null) return abi.OMNI_ERR_INVALID_ARGS;

    const req = request[0];
    if (!std.math.isFinite(req.screen_x) or
        !std.math.isFinite(req.screen_y) or
        !isFiniteNonNegative(req.screen_width) or
        !isFiniteNonNegative(req.screen_height) or
        !isFiniteNonNegative(req.inner_gap) or
        !isFiniteNonNegative(req.outer_gap_top) or
        !isFiniteNonNegative(req.outer_gap_bottom) or
        !isFiniteNonNegative(req.outer_gap_left) or
        !isFiniteNonNegative(req.outer_gap_right) or
        !isFiniteNonNegative(req.single_window_aspect_width) or
        !isFiniteNonNegative(req.single_window_aspect_height) or
        !isFiniteNonNegative(req.single_window_aspect_tolerance))
    {
        return abi.OMNI_ERR_INVALID_ARGS;
    }

    var rc = validateConstraints(constraints, constraint_count);
    if (rc != abi.OMNI_OK) return rc;

    out_frame_count[0] = 0;

    if (ctx.node_count == 0) {
        ctx.cached_frame_count = 0;
        return abi.OMNI_OK;
    }

    if (ctx.seed_state.root_node_index < 0) return abi.OMNI_ERR_OUT_OF_RANGE;
    const root_idx = std.math.cast(usize, ctx.seed_state.root_node_index) orelse return abi.OMNI_ERR_OUT_OF_RANGE;
    if (root_idx >= ctx.node_count) return abi.OMNI_ERR_OUT_OF_RANGE;

    var scratch = LayoutScratch{
        .frame_count = 0,
        .frames = undefined,
        .has_min_size = [_]u8{0} ** abi.OMNI_DWINDLE_MAX_NODES,
        .min_sizes = undefined,
    };

    const screen = Rect{
        .x = req.screen_x,
        .y = req.screen_y,
        .width = req.screen_width,
        .height = req.screen_height,
    };
    const tiling_area = applyOuterGapsOnly(screen, req);

    var window_count: usize = 0;
    rc = countWindowLeaves(ctx, root_idx, &window_count);
    if (rc != abi.OMNI_OK) return rc;

    if (window_count == 0) {
        ctx.cached_frame_count = 0;
        return abi.OMNI_OK;
    }

    if (window_count > abi.MAX_WINDOWS) return abi.OMNI_ERR_OUT_OF_RANGE;

    if (window_count == 1) {
        const leaf_idx = findSingleWindowLeaf(ctx, root_idx) orelse return abi.OMNI_ERR_INVALID_ARGS;
        const leaf = ctx.nodes[leaf_idx];
        const target = if (leaf.is_fullscreen != 0)
            screen
        else
            singleWindowRect(tiling_area, req);
        rc = appendFrame(&scratch, leaf.window_id, target);
        if (rc != abi.OMNI_OK) return rc;
    } else {
        rc = layoutRecursive(
            ctx,
            constraints,
            constraint_count,
            req,
            &scratch,
            root_idx,
            tiling_area,
            tiling_area,
        );
        if (rc != abi.OMNI_OK) return rc;
    }

    out_frame_count[0] = scratch.frame_count;

    if (out_frame_capacity < scratch.frame_count) {
        ctx.cached_frame_count = 0;
        return abi.OMNI_ERR_OUT_OF_RANGE;
    }

    if (out_frames != null and scratch.frame_count > 0) {
        for (0..scratch.frame_count) |idx| {
            out_frames[idx] = scratch.frames[idx];
        }
    }

    ctx.cached_frame_count = scratch.frame_count;
    for (0..scratch.frame_count) |idx| {
        ctx.cached_frames[idx] = scratch.frames[idx];
    }
    return abi.OMNI_OK;
}

pub fn omni_dwindle_ctx_find_neighbor_impl(
    context: [*c]const OmniDwindleLayoutContext,
    window_id: abi.OmniUuid128,
    direction: u8,
    inner_gap: f64,
    out_has_neighbor: [*c]u8,
    out_neighbor_window_id: [*c]abi.OmniUuid128,
) i32 {
    const ctx = asConstContext(context) orelse return abi.OMNI_ERR_INVALID_ARGS;
    if (out_has_neighbor == null or out_neighbor_window_id == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (!isValidDirection(direction)) return abi.OMNI_ERR_INVALID_ARGS;
    if (!isFiniteNonNegative(inner_gap)) return abi.OMNI_ERR_INVALID_ARGS;
    if (isZeroUuid(window_id)) return abi.OMNI_ERR_INVALID_ARGS;

    out_has_neighbor[0] = 0;
    out_neighbor_window_id[0] = zeroUuid();

    if (ctx.cached_frame_count == 0) return abi.OMNI_OK;
    if (ctx.cached_frame_count > abi.MAX_WINDOWS) return abi.OMNI_ERR_OUT_OF_RANGE;

    var source_rect: ?Rect = null;
    for (0..ctx.cached_frame_count) |idx| {
        const frame = ctx.cached_frames[idx];
        if (uuidEqual(frame.window_id, window_id)) {
            source_rect = frameToRect(frame);
            break;
        }
    }
    if (source_rect == null) return abi.OMNI_OK;

    var best_overlap: f64 = 0.0;
    var best_window: abi.OmniUuid128 = zeroUuid();
    var found = false;

    for (0..ctx.cached_frame_count) |idx| {
        const candidate = ctx.cached_frames[idx];
        if (uuidEqual(candidate.window_id, window_id)) continue;

        if (calculateDirectionalOverlap(source_rect.?, frameToRect(candidate), direction, inner_gap)) |overlap| {
            if (!found or overlap > best_overlap) {
                found = true;
                best_overlap = overlap;
                best_window = candidate.window_id;
            }
        }
    }

    if (found) {
        out_has_neighbor[0] = 1;
        out_neighbor_window_id[0] = best_window;
    }
    return abi.OMNI_OK;
}
