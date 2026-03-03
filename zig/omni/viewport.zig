const abi = @import("abi_types.zig");
const geometry = @import("geometry.zig");

fn parseCenterMode(mode: u8) ?u8 {
    return switch (mode) {
        abi.OMNI_CENTER_NEVER, abi.OMNI_CENTER_ALWAYS, abi.OMNI_CENTER_ON_OVERFLOW => mode,
        else => null,
    };
}

fn containerPositionFromSpans(spans: [*c]const f64, span_count: usize, index: usize, gap: f64) f64 {
    _ = span_count;
    var pos: f64 = 0.0;
    var i: usize = 0;
    while (i < index) : (i += 1) {
        pos += spans[i] + gap;
    }
    return pos;
}

fn totalSpanFromSpans(spans: [*c]const f64, span_count: usize, gap: f64) f64 {
    if (span_count == 0) return 0.0;

    var total: f64 = 0.0;
    for (0..span_count) |i| {
        total += spans[i];
    }
    total += @as(f64, @floatFromInt(span_count - 1)) * gap;
    return total;
}

fn computeCenteredOffsetFromSpans(
    spans: [*c]const f64,
    span_count: usize,
    container_index: usize,
    gap: f64,
    viewport_span: f64,
) f64 {
    if (span_count == 0 or container_index >= span_count) return 0.0;

    const total = totalSpanFromSpans(spans, span_count, gap);
    const pos = containerPositionFromSpans(spans, span_count, container_index, gap);

    if (total <= viewport_span) {
        return -pos - (viewport_span - total) / 2.0;
    }

    const container_size = spans[container_index];
    const centered_offset = -(viewport_span - container_size) / 2.0;
    const max_offset: f64 = 0.0;
    const min_offset = viewport_span - total;
    return geometry.clampFloat(centered_offset, min_offset, max_offset);
}

fn computeFitOffset(
    current_view_pos: f64,
    view_span: f64,
    target_pos: f64,
    target_span: f64,
    gaps: f64,
) f64 {
    if (view_span <= target_span) {
        return 0.0;
    }

    const padding = geometry.clampFloat((view_span - target_span) / 2.0, 0.0, gaps);
    const new_pos = target_pos - padding;
    const new_end_pos = target_pos + target_span + padding;

    if (current_view_pos <= new_pos and new_end_pos <= current_view_pos + view_span) {
        return -(target_pos - current_view_pos);
    }

    const dist_to_start = @abs(current_view_pos - new_pos);
    const dist_to_end = @abs((current_view_pos + view_span) - new_end_pos);

    if (dist_to_start <= dist_to_end) {
        return -padding;
    }

    return -(view_span - padding - target_span);
}

fn considerSnapPoint(
    candidate_view_pos: f64,
    candidate_col_idx: usize,
    projected_view_pos: f64,
    min_view_pos: f64,
    max_view_pos: f64,
    best_is_set: *bool,
    best_view_pos: *f64,
    best_col_idx: *usize,
    best_distance: *f64,
) void {
    const clamped = @min(@max(candidate_view_pos, min_view_pos), max_view_pos);
    const distance = @abs(clamped - projected_view_pos);
    if (!best_is_set.* or distance < best_distance.*) {
        best_is_set.* = true;
        best_view_pos.* = clamped;
        best_col_idx.* = candidate_col_idx;
        best_distance.* = distance;
    }
}

pub fn omni_viewport_compute_visible_offset_impl(
    spans: [*c]const f64,
    span_count: usize,
    container_index: usize,
    gap: f64,
    viewport_span: f64,
    current_view_start: f64,
    center_mode: u8,
    always_center_single_column: u8,
    from_container_index: i64,
    out_target_offset: [*c]f64,
) i32 {
    if (out_target_offset == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (span_count == 0 or container_index >= span_count) return abi.OMNI_ERR_OUT_OF_RANGE;
    if (spans == null) return abi.OMNI_ERR_INVALID_ARGS;

    const parsed_mode = parseCenterMode(center_mode) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const effective_center_mode = if (span_count == 1 and always_center_single_column != 0)
        abi.OMNI_CENTER_ALWAYS
    else
        parsed_mode;

    const target_pos = containerPositionFromSpans(spans, span_count, container_index, gap);
    const target_size = spans[container_index];

    var target_offset: f64 = 0.0;

    switch (effective_center_mode) {
        abi.OMNI_CENTER_ALWAYS => {
            target_offset = computeCenteredOffsetFromSpans(
                spans,
                span_count,
                container_index,
                gap,
                viewport_span,
            );
        },
        abi.OMNI_CENTER_ON_OVERFLOW => {
            if (target_size > viewport_span) {
                target_offset = computeCenteredOffsetFromSpans(
                    spans,
                    span_count,
                    container_index,
                    gap,
                    viewport_span,
                );
            } else if (from_container_index != -1 and from_container_index != @as(i64, @intCast(container_index))) {
                const source_idx = if (from_container_index > @as(i64, @intCast(container_index)))
                    @min(container_index + 1, span_count - 1)
                else
                    if (container_index > 0) container_index - 1 else 0;

                const source_pos = containerPositionFromSpans(spans, span_count, source_idx, gap);
                const source_size = spans[source_idx];

                const total_span_needed: f64 = if (source_pos < target_pos)
                    target_pos - source_pos + target_size + gap * 2.0
                else
                    source_pos - target_pos + source_size + gap * 2.0;

                if (total_span_needed <= viewport_span) {
                    target_offset = computeFitOffset(
                        current_view_start,
                        viewport_span,
                        target_pos,
                        target_size,
                        gap,
                    );
                } else {
                    target_offset = computeCenteredOffsetFromSpans(
                        spans,
                        span_count,
                        container_index,
                        gap,
                        viewport_span,
                    );
                }
            } else {
                target_offset = computeFitOffset(
                    current_view_start,
                    viewport_span,
                    target_pos,
                    target_size,
                    gap,
                );
            }
        },
        abi.OMNI_CENTER_NEVER => {
            target_offset = computeFitOffset(
                current_view_start,
                viewport_span,
                target_pos,
                target_size,
                gap,
            );
        },
        else => return abi.OMNI_ERR_INVALID_ARGS,
    }

    const total = totalSpanFromSpans(spans, span_count, gap);
    const max_offset: f64 = 0.0;
    const min_offset = viewport_span - total;
    if (min_offset < max_offset) {
        target_offset = geometry.clampFloat(target_offset, min_offset, max_offset);
    }

    out_target_offset[0] = target_offset;
    return abi.OMNI_OK;
}

pub fn omni_viewport_find_snap_target_impl(
    spans: [*c]const f64,
    span_count: usize,
    gap: f64,
    viewport_span: f64,
    projected_view_pos: f64,
    current_view_pos: f64,
    center_mode: u8,
    always_center_single_column: u8,
    out_result: [*c]abi.OmniSnapResult,
) i32 {
    if (out_result == null) return abi.OMNI_ERR_INVALID_ARGS;
    if (span_count == 0) {
        out_result[0] = .{ .view_pos = 0.0, .column_index = 0 };
        return abi.OMNI_OK;
    }
    if (spans == null) return abi.OMNI_ERR_INVALID_ARGS;

    const parsed_mode = parseCenterMode(center_mode) orelse return abi.OMNI_ERR_INVALID_ARGS;
    const effective_center_mode = if (span_count == 1 and always_center_single_column != 0)
        abi.OMNI_CENTER_ALWAYS
    else
        parsed_mode;

    const vw = viewport_span;
    const gaps = gap;
    const total_w = totalSpanFromSpans(spans, span_count, gap);
    const max_view_pos: f64 = 0.0;
    const min_view_pos = vw - total_w;

    var best_is_set = false;
    var best_view_pos: f64 = 0.0;
    var best_col_idx: usize = 0;
    var best_distance: f64 = 0.0;

    if (effective_center_mode == abi.OMNI_CENTER_ALWAYS) {
        for (0..span_count) |idx| {
            const col_x = containerPositionFromSpans(spans, span_count, idx, gap);
            const offset = computeCenteredOffsetFromSpans(spans, span_count, idx, gap, viewport_span);
            const snap_view_pos = col_x + offset;
            considerSnapPoint(
                snap_view_pos,
                idx,
                projected_view_pos,
                min_view_pos,
                max_view_pos,
                &best_is_set,
                &best_view_pos,
                &best_col_idx,
                &best_distance,
            );
        }
    } else {
        var col_x: f64 = 0.0;
        for (0..span_count) |idx| {
            const col_w = spans[idx];
            const padding = geometry.clampFloat((vw - col_w) / 2.0, 0.0, gaps);
            const left_snap = col_x - padding;
            const right_snap = col_x + col_w + padding - vw;

            considerSnapPoint(
                left_snap,
                idx,
                projected_view_pos,
                min_view_pos,
                max_view_pos,
                &best_is_set,
                &best_view_pos,
                &best_col_idx,
                &best_distance,
            );
            if (right_snap != left_snap) {
                considerSnapPoint(
                    right_snap,
                    idx,
                    projected_view_pos,
                    min_view_pos,
                    max_view_pos,
                    &best_is_set,
                    &best_view_pos,
                    &best_col_idx,
                    &best_distance,
                );
            }

            col_x += col_w + gaps;
        }
    }

    if (!best_is_set) {
        out_result[0] = .{ .view_pos = 0.0, .column_index = 0 };
        return abi.OMNI_OK;
    }

    var new_col_idx = best_col_idx;

    if (effective_center_mode != abi.OMNI_CENTER_ALWAYS) {
        const scrolling_right = projected_view_pos >= current_view_pos;
        if (scrolling_right) {
            var idx = new_col_idx + 1;
            while (idx < span_count) : (idx += 1) {
                const col_x = containerPositionFromSpans(spans, span_count, idx, gap);
                const col_w = spans[idx];
                const padding = geometry.clampFloat((vw - col_w) / 2.0, 0.0, gaps);
                if (best_view_pos + vw >= col_x + col_w + padding) {
                    new_col_idx = idx;
                } else {
                    break;
                }
            }
        } else {
            var idx_i: isize = @intCast(new_col_idx);
            while (idx_i > 0) {
                idx_i -= 1;
                const idx: usize = @intCast(idx_i);
                const col_x = containerPositionFromSpans(spans, span_count, idx, gap);
                const col_w = spans[idx];
                const padding = geometry.clampFloat((vw - col_w) / 2.0, 0.0, gaps);
                if (col_x - padding >= best_view_pos) {
                    new_col_idx = idx;
                } else {
                    break;
                }
            }
        }
    }

    out_result[0] = .{ .view_pos = best_view_pos, .column_index = new_col_idx };
    return abi.OMNI_OK;
}
