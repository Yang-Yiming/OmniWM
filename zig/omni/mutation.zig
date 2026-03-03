const std = @import("std");
const abi = @import("abi_types.zig");
const geometry = @import("geometry.zig");

const OmniNiriStateColumnInput = abi.OmniNiriStateColumnInput;
const OmniNiriStateWindowInput = abi.OmniNiriStateWindowInput;
const OmniNiriMutationRequest = abi.OmniNiriMutationRequest;
const OmniNiriMutationResult = abi.OmniNiriMutationResult;
const OmniNiriMutationEdit = abi.OmniNiriMutationEdit;

const OMNI_OK = abi.OMNI_OK;
const OMNI_ERR_INVALID_ARGS = abi.OMNI_ERR_INVALID_ARGS;
const OMNI_ERR_OUT_OF_RANGE = abi.OMNI_ERR_OUT_OF_RANGE;

const OMNI_NIRI_DIRECTION_LEFT = abi.OMNI_NIRI_DIRECTION_LEFT;
const OMNI_NIRI_DIRECTION_RIGHT = abi.OMNI_NIRI_DIRECTION_RIGHT;
const OMNI_NIRI_DIRECTION_UP = abi.OMNI_NIRI_DIRECTION_UP;
const OMNI_NIRI_DIRECTION_DOWN = abi.OMNI_NIRI_DIRECTION_DOWN;

const OMNI_NIRI_INSERT_BEFORE = abi.OMNI_NIRI_INSERT_BEFORE;
const OMNI_NIRI_INSERT_AFTER = abi.OMNI_NIRI_INSERT_AFTER;

const OMNI_NIRI_MUTATION_OP_MOVE_WINDOW_VERTICAL = abi.OMNI_NIRI_MUTATION_OP_MOVE_WINDOW_VERTICAL;
const OMNI_NIRI_MUTATION_OP_SWAP_WINDOW_VERTICAL = abi.OMNI_NIRI_MUTATION_OP_SWAP_WINDOW_VERTICAL;
const OMNI_NIRI_MUTATION_OP_MOVE_WINDOW_HORIZONTAL = abi.OMNI_NIRI_MUTATION_OP_MOVE_WINDOW_HORIZONTAL;
const OMNI_NIRI_MUTATION_OP_SWAP_WINDOW_HORIZONTAL = abi.OMNI_NIRI_MUTATION_OP_SWAP_WINDOW_HORIZONTAL;
const OMNI_NIRI_MUTATION_OP_SWAP_WINDOWS_BY_MOVE = abi.OMNI_NIRI_MUTATION_OP_SWAP_WINDOWS_BY_MOVE;
const OMNI_NIRI_MUTATION_OP_INSERT_WINDOW_BY_MOVE = abi.OMNI_NIRI_MUTATION_OP_INSERT_WINDOW_BY_MOVE;

const OMNI_NIRI_MUTATION_EDIT_SET_ACTIVE_TILE = abi.OMNI_NIRI_MUTATION_EDIT_SET_ACTIVE_TILE;
const OMNI_NIRI_MUTATION_EDIT_SWAP_WINDOWS = abi.OMNI_NIRI_MUTATION_EDIT_SWAP_WINDOWS;
const OMNI_NIRI_MUTATION_EDIT_MOVE_WINDOW_TO_COLUMN_INDEX = abi.OMNI_NIRI_MUTATION_EDIT_MOVE_WINDOW_TO_COLUMN_INDEX;
const OMNI_NIRI_MUTATION_EDIT_SWAP_COLUMN_WIDTH_STATE = abi.OMNI_NIRI_MUTATION_EDIT_SWAP_COLUMN_WIDTH_STATE;
const OMNI_NIRI_MUTATION_EDIT_SWAP_WINDOW_SIZE_HEIGHT = abi.OMNI_NIRI_MUTATION_EDIT_SWAP_WINDOW_SIZE_HEIGHT;
const OMNI_NIRI_MUTATION_EDIT_RESET_WINDOW_SIZE_HEIGHT = abi.OMNI_NIRI_MUTATION_EDIT_RESET_WINDOW_SIZE_HEIGHT;
const OMNI_NIRI_MUTATION_EDIT_REMOVE_COLUMN_IF_EMPTY = abi.OMNI_NIRI_MUTATION_EDIT_REMOVE_COLUMN_IF_EMPTY;
const OMNI_NIRI_MUTATION_EDIT_REFRESH_TABBED_VISIBILITY = abi.OMNI_NIRI_MUTATION_EDIT_REFRESH_TABBED_VISIBILITY;
const OMNI_NIRI_MUTATION_EDIT_DELEGATE_MOVE_COLUMN = abi.OMNI_NIRI_MUTATION_EDIT_DELEGATE_MOVE_COLUMN;

const OMNI_NIRI_MUTATION_MAX_EDITS = abi.OMNI_NIRI_MUTATION_MAX_EDITS;

const SelectedContext = struct {
    column_index: usize,
    row_index: usize,
    window_index: usize,
};

fn wrappedColumnIndex(idx: i64, total: usize, infinite_loop: bool) ?usize {
    if (total == 0) return null;

    if (infinite_loop) {
        const modulo = std.math.cast(i64, total) orelse return null;
        const wrapped = @mod(idx, modulo);
        return std.math.cast(usize, wrapped);
    }

    if (idx < 0) return null;
    const casted = std.math.cast(usize, idx) orelse return null;
    if (casted >= total) return null;
    return casted;
}

fn initMutationResult(out_result: *OmniNiriMutationResult) void {
    const empty_edit = OmniNiriMutationEdit{
        .kind = OMNI_NIRI_MUTATION_EDIT_SET_ACTIVE_TILE,
        .subject_index = -1,
        .related_index = -1,
        .value_a = -1,
        .value_b = -1,
    };
    out_result.* = .{
        .applied = 0,
        .has_target_window = 0,
        .target_window_index = -1,
        .edit_count = 0,
        .edits = [_]OmniNiriMutationEdit{empty_edit} ** OMNI_NIRI_MUTATION_MAX_EDITS,
    };
}

fn addMutationEdit(
    out_result: *OmniNiriMutationResult,
    kind: u8,
    subject_index: i64,
    related_index: i64,
    value_a: i64,
    value_b: i64,
) i32 {
    if (out_result.edit_count >= OMNI_NIRI_MUTATION_MAX_EDITS) return OMNI_ERR_OUT_OF_RANGE;
    out_result.edits[out_result.edit_count] = .{
        .kind = kind,
        .subject_index = subject_index,
        .related_index = related_index,
        .value_a = value_a,
        .value_b = value_b,
    };
    out_result.edit_count += 1;
    return OMNI_OK;
}

fn setMutationTargetWindow(out_result: *OmniNiriMutationResult, window_index: usize) i32 {
    const target_i64 = std.math.cast(i64, window_index) orelse return OMNI_ERR_OUT_OF_RANGE;
    out_result.has_target_window = 1;
    out_result.target_window_index = target_i64;
    return OMNI_OK;
}

fn parseWindowContextByIndex(
    columns: [*c]const OmniNiriStateColumnInput,
    windows: [*c]const OmniNiriStateWindowInput,
    column_count: usize,
    window_count: usize,
    window_index_raw: i64,
    out_context: *SelectedContext,
) i32 {
    const window_index = std.math.cast(usize, window_index_raw) orelse return OMNI_ERR_OUT_OF_RANGE;
    if (window_index >= window_count) return OMNI_ERR_OUT_OF_RANGE;

    const column_index = windows[window_index].column_index;
    if (column_index >= column_count) return OMNI_ERR_OUT_OF_RANGE;

    const column = columns[column_index];
    if (!geometry.rangeContains(column.window_start, column.window_count, window_index)) return OMNI_ERR_OUT_OF_RANGE;

    out_context.* = .{
        .column_index = column_index,
        .row_index = window_index - column.window_start,
        .window_index = window_index,
    };
    return OMNI_OK;
}

fn adjustedTabbedActiveAfterRemoval(column: OmniNiriStateColumnInput, removed_row: usize) usize {
    if (column.window_count == 0) return 0;
    var active = column.active_tile_idx;

    if (removed_row == active) {
        if (column.window_count > 1 and removed_row >= column.window_count - 1) {
            active = if (removed_row > 0) removed_row - 1 else 0;
        }
    } else if (removed_row < active) {
        active = if (active > 0) active - 1 else 0;
    }

    return active;
}

fn clampedActiveAfterRemoval(column: OmniNiriStateColumnInput) usize {
    if (column.window_count <= 1) return 0;
    const max_idx_after = column.window_count - 2;
    return @min(column.active_tile_idx, max_idx_after);
}

fn planMoveWindowVertical(
    columns: [*c]const OmniNiriStateColumnInput,
    selected: SelectedContext,
    direction: u8,
    out_result: *OmniNiriMutationResult,
) i32 {
    const source_column = columns[selected.column_index];
    if (source_column.window_count == 0) return OMNI_OK;

    const target_row_opt: ?usize = switch (direction) {
        OMNI_NIRI_DIRECTION_UP => if (selected.row_index + 1 < source_column.window_count) selected.row_index + 1 else null,
        OMNI_NIRI_DIRECTION_DOWN => if (selected.row_index > 0) selected.row_index - 1 else null,
        else => return OMNI_ERR_INVALID_ARGS,
    };

    const target_row = target_row_opt orelse return OMNI_OK;
    const target_window_index = source_column.window_start + target_row;

    var rc = addMutationEdit(
        out_result,
        OMNI_NIRI_MUTATION_EDIT_SWAP_WINDOWS,
        std.math.cast(i64, selected.window_index) orelse return OMNI_ERR_OUT_OF_RANGE,
        std.math.cast(i64, target_window_index) orelse return OMNI_ERR_OUT_OF_RANGE,
        -1,
        -1,
    );
    if (rc != OMNI_OK) return rc;

    if (source_column.is_tabbed != 0) {
        if (selected.row_index == source_column.active_tile_idx) {
            rc = addMutationEdit(
                out_result,
                OMNI_NIRI_MUTATION_EDIT_SET_ACTIVE_TILE,
                std.math.cast(i64, selected.column_index) orelse return OMNI_ERR_OUT_OF_RANGE,
                -1,
                std.math.cast(i64, target_row) orelse return OMNI_ERR_OUT_OF_RANGE,
                -1,
            );
            if (rc != OMNI_OK) return rc;
        } else if (target_row == source_column.active_tile_idx) {
            rc = addMutationEdit(
                out_result,
                OMNI_NIRI_MUTATION_EDIT_SET_ACTIVE_TILE,
                std.math.cast(i64, selected.column_index) orelse return OMNI_ERR_OUT_OF_RANGE,
                -1,
                std.math.cast(i64, selected.row_index) orelse return OMNI_ERR_OUT_OF_RANGE,
                -1,
            );
            if (rc != OMNI_OK) return rc;
        }
    }

    rc = setMutationTargetWindow(out_result, selected.window_index);
    if (rc != OMNI_OK) return rc;
    out_result.applied = 1;
    return OMNI_OK;
}

fn planMoveWindowHorizontal(
    columns: [*c]const OmniNiriStateColumnInput,
    column_count: usize,
    selected: SelectedContext,
    direction: u8,
    infinite_loop: bool,
    max_windows_per_column: usize,
    out_result: *OmniNiriMutationResult,
) i32 {
    const source_column = columns[selected.column_index];
    const source_col_i64 = std.math.cast(i64, selected.column_index) orelse return OMNI_ERR_OUT_OF_RANGE;
    const step: i64 = switch (direction) {
        OMNI_NIRI_DIRECTION_RIGHT => 1,
        OMNI_NIRI_DIRECTION_LEFT => -1,
        else => return OMNI_ERR_INVALID_ARGS,
    };

    const target_col_index = wrappedColumnIndex(source_col_i64 + step, column_count, infinite_loop) orelse return OMNI_OK;
    if (target_col_index == selected.column_index) return OMNI_OK;
    const target_column = columns[target_col_index];
    if (target_column.window_count >= max_windows_per_column) return OMNI_OK;

    var rc = addMutationEdit(
        out_result,
        OMNI_NIRI_MUTATION_EDIT_MOVE_WINDOW_TO_COLUMN_INDEX,
        std.math.cast(i64, selected.window_index) orelse return OMNI_ERR_OUT_OF_RANGE,
        std.math.cast(i64, target_col_index) orelse return OMNI_ERR_OUT_OF_RANGE,
        std.math.cast(i64, target_column.window_count) orelse return OMNI_ERR_OUT_OF_RANGE,
        -1,
    );
    if (rc != OMNI_OK) return rc;

    if (source_column.is_tabbed != 0) {
        const remaining_count = source_column.window_count - 1;
        if (remaining_count > 0) {
            const updated_active = adjustedTabbedActiveAfterRemoval(source_column, selected.row_index);
            rc = addMutationEdit(
                out_result,
                OMNI_NIRI_MUTATION_EDIT_SET_ACTIVE_TILE,
                std.math.cast(i64, selected.column_index) orelse return OMNI_ERR_OUT_OF_RANGE,
                -1,
                std.math.cast(i64, updated_active) orelse return OMNI_ERR_OUT_OF_RANGE,
                -1,
            );
            if (rc != OMNI_OK) return rc;
            rc = addMutationEdit(
                out_result,
                OMNI_NIRI_MUTATION_EDIT_REFRESH_TABBED_VISIBILITY,
                std.math.cast(i64, selected.column_index) orelse return OMNI_ERR_OUT_OF_RANGE,
                -1,
                -1,
                -1,
            );
            if (rc != OMNI_OK) return rc;
        }
    } else {
        const remaining_count = source_column.window_count - 1;
        if (remaining_count > 0) {
            const clamped_active = @min(source_column.active_tile_idx, remaining_count - 1);
            rc = addMutationEdit(
                out_result,
                OMNI_NIRI_MUTATION_EDIT_SET_ACTIVE_TILE,
                std.math.cast(i64, selected.column_index) orelse return OMNI_ERR_OUT_OF_RANGE,
                -1,
                std.math.cast(i64, clamped_active) orelse return OMNI_ERR_OUT_OF_RANGE,
                -1,
            );
            if (rc != OMNI_OK) return rc;
        }
    }

    if (target_column.is_tabbed != 0) {
        rc = addMutationEdit(
            out_result,
            OMNI_NIRI_MUTATION_EDIT_REFRESH_TABBED_VISIBILITY,
            std.math.cast(i64, target_col_index) orelse return OMNI_ERR_OUT_OF_RANGE,
            -1,
            -1,
            -1,
        );
        if (rc != OMNI_OK) return rc;
    }

    rc = addMutationEdit(
        out_result,
        OMNI_NIRI_MUTATION_EDIT_REMOVE_COLUMN_IF_EMPTY,
        std.math.cast(i64, selected.column_index) orelse return OMNI_ERR_OUT_OF_RANGE,
        -1,
        -1,
        -1,
    );
    if (rc != OMNI_OK) return rc;

    rc = setMutationTargetWindow(out_result, selected.window_index);
    if (rc != OMNI_OK) return rc;
    out_result.applied = 1;
    return OMNI_OK;
}

fn planSwapWindowHorizontal(
    columns: [*c]const OmniNiriStateColumnInput,
    column_count: usize,
    selected: SelectedContext,
    direction: u8,
    infinite_loop: bool,
    out_result: *OmniNiriMutationResult,
) i32 {
    const source_col_i64 = std.math.cast(i64, selected.column_index) orelse return OMNI_ERR_OUT_OF_RANGE;
    const step: i64 = switch (direction) {
        OMNI_NIRI_DIRECTION_RIGHT => 1,
        OMNI_NIRI_DIRECTION_LEFT => -1,
        else => return OMNI_ERR_INVALID_ARGS,
    };

    const target_col_index = wrappedColumnIndex(source_col_i64 + step, column_count, infinite_loop) orelse return OMNI_OK;
    if (target_col_index == selected.column_index) return OMNI_OK;

    const source_column = columns[selected.column_index];
    const target_column = columns[target_col_index];
    if (target_column.window_count == 0) return OMNI_OK;

    if (source_column.window_count == 1 and target_column.window_count == 1) {
        const rc_delegate = addMutationEdit(
            out_result,
            OMNI_NIRI_MUTATION_EDIT_DELEGATE_MOVE_COLUMN,
            std.math.cast(i64, selected.column_index) orelse return OMNI_ERR_OUT_OF_RANGE,
            -1,
            std.math.cast(i64, direction) orelse return OMNI_ERR_OUT_OF_RANGE,
            -1,
        );
        if (rc_delegate != OMNI_OK) return rc_delegate;
        out_result.applied = 1;
        return OMNI_OK;
    }

    const source_active_row = @min(source_column.active_tile_idx, source_column.window_count - 1);
    const target_active_row = @min(target_column.active_tile_idx, target_column.window_count - 1);
    const source_active_window = source_column.window_start + source_active_row;
    const target_active_window = target_column.window_start + target_active_row;

    var rc = addMutationEdit(
        out_result,
        OMNI_NIRI_MUTATION_EDIT_SWAP_WINDOWS,
        std.math.cast(i64, source_active_window) orelse return OMNI_ERR_OUT_OF_RANGE,
        std.math.cast(i64, target_active_window) orelse return OMNI_ERR_OUT_OF_RANGE,
        -1,
        -1,
    );
    if (rc != OMNI_OK) return rc;

    rc = addMutationEdit(
        out_result,
        OMNI_NIRI_MUTATION_EDIT_SWAP_COLUMN_WIDTH_STATE,
        std.math.cast(i64, selected.column_index) orelse return OMNI_ERR_OUT_OF_RANGE,
        std.math.cast(i64, target_col_index) orelse return OMNI_ERR_OUT_OF_RANGE,
        -1,
        -1,
    );
    if (rc != OMNI_OK) return rc;

    rc = addMutationEdit(
        out_result,
        OMNI_NIRI_MUTATION_EDIT_SET_ACTIVE_TILE,
        std.math.cast(i64, selected.column_index) orelse return OMNI_ERR_OUT_OF_RANGE,
        -1,
        std.math.cast(i64, source_active_row) orelse return OMNI_ERR_OUT_OF_RANGE,
        -1,
    );
    if (rc != OMNI_OK) return rc;

    rc = addMutationEdit(
        out_result,
        OMNI_NIRI_MUTATION_EDIT_SET_ACTIVE_TILE,
        std.math.cast(i64, target_col_index) orelse return OMNI_ERR_OUT_OF_RANGE,
        -1,
        std.math.cast(i64, target_active_row) orelse return OMNI_ERR_OUT_OF_RANGE,
        -1,
    );
    if (rc != OMNI_OK) return rc;

    if (source_column.is_tabbed != 0) {
        rc = addMutationEdit(
            out_result,
            OMNI_NIRI_MUTATION_EDIT_REFRESH_TABBED_VISIBILITY,
            std.math.cast(i64, selected.column_index) orelse return OMNI_ERR_OUT_OF_RANGE,
            -1,
            -1,
            -1,
        );
        if (rc != OMNI_OK) return rc;
    }
    if (target_column.is_tabbed != 0) {
        rc = addMutationEdit(
            out_result,
            OMNI_NIRI_MUTATION_EDIT_REFRESH_TABBED_VISIBILITY,
            std.math.cast(i64, target_col_index) orelse return OMNI_ERR_OUT_OF_RANGE,
            -1,
            -1,
            -1,
        );
        if (rc != OMNI_OK) return rc;
    }

    rc = setMutationTargetWindow(out_result, source_active_window);
    if (rc != OMNI_OK) return rc;
    out_result.applied = 1;
    return OMNI_OK;
}

fn planSwapWindowsByMove(
    columns: [*c]const OmniNiriStateColumnInput,
    source: SelectedContext,
    target: SelectedContext,
    out_result: *OmniNiriMutationResult,
) i32 {
    const source_column = columns[source.column_index];
    const target_column = columns[target.column_index];

    var rc = addMutationEdit(
        out_result,
        OMNI_NIRI_MUTATION_EDIT_SWAP_WINDOWS,
        std.math.cast(i64, source.window_index) orelse return OMNI_ERR_OUT_OF_RANGE,
        std.math.cast(i64, target.window_index) orelse return OMNI_ERR_OUT_OF_RANGE,
        -1,
        -1,
    );
    if (rc != OMNI_OK) return rc;

    if (source.column_index != target.column_index) {
        rc = addMutationEdit(
            out_result,
            OMNI_NIRI_MUTATION_EDIT_SWAP_WINDOW_SIZE_HEIGHT,
            std.math.cast(i64, source.window_index) orelse return OMNI_ERR_OUT_OF_RANGE,
            std.math.cast(i64, target.window_index) orelse return OMNI_ERR_OUT_OF_RANGE,
            -1,
            -1,
        );
        if (rc != OMNI_OK) return rc;
    }

    if (source_column.is_tabbed != 0) {
        rc = addMutationEdit(
            out_result,
            OMNI_NIRI_MUTATION_EDIT_SET_ACTIVE_TILE,
            std.math.cast(i64, source.column_index) orelse return OMNI_ERR_OUT_OF_RANGE,
            -1,
            std.math.cast(i64, @min(source_column.active_tile_idx, source_column.window_count - 1)) orelse return OMNI_ERR_OUT_OF_RANGE,
            -1,
        );
        if (rc != OMNI_OK) return rc;
    }

    if (target.column_index != source.column_index and target_column.is_tabbed != 0) {
        rc = addMutationEdit(
            out_result,
            OMNI_NIRI_MUTATION_EDIT_SET_ACTIVE_TILE,
            std.math.cast(i64, target.column_index) orelse return OMNI_ERR_OUT_OF_RANGE,
            -1,
            std.math.cast(i64, @min(target_column.active_tile_idx, target_column.window_count - 1)) orelse return OMNI_ERR_OUT_OF_RANGE,
            -1,
        );
        if (rc != OMNI_OK) return rc;
    }

    rc = setMutationTargetWindow(out_result, source.window_index);
    if (rc != OMNI_OK) return rc;
    out_result.applied = 1;
    return OMNI_OK;
}

fn planInsertWindowByMove(
    columns: [*c]const OmniNiriStateColumnInput,
    source: SelectedContext,
    target: SelectedContext,
    insert_position: u8,
    out_result: *OmniNiriMutationResult,
) i32 {
    if (insert_position != OMNI_NIRI_INSERT_BEFORE and insert_position != OMNI_NIRI_INSERT_AFTER) {
        return OMNI_ERR_INVALID_ARGS;
    }

    const source_column = columns[source.column_index];
    const target_column = columns[target.column_index];
    const same_column = source.column_index == target.column_index;

    var insert_row: usize = 0;
    if (same_column) {
        var current_target_row = target.row_index;
        if (source.row_index < target.row_index and current_target_row > 0) {
            current_target_row -= 1;
        }
        insert_row = if (insert_position == OMNI_NIRI_INSERT_BEFORE) current_target_row else current_target_row + 1;
    } else {
        insert_row = if (insert_position == OMNI_NIRI_INSERT_BEFORE) target.row_index else target.row_index + 1;
    }

    var rc = addMutationEdit(
        out_result,
        OMNI_NIRI_MUTATION_EDIT_MOVE_WINDOW_TO_COLUMN_INDEX,
        std.math.cast(i64, source.window_index) orelse return OMNI_ERR_OUT_OF_RANGE,
        std.math.cast(i64, target.column_index) orelse return OMNI_ERR_OUT_OF_RANGE,
        std.math.cast(i64, insert_row) orelse return OMNI_ERR_OUT_OF_RANGE,
        -1,
    );
    if (rc != OMNI_OK) return rc;

    rc = addMutationEdit(
        out_result,
        OMNI_NIRI_MUTATION_EDIT_RESET_WINDOW_SIZE_HEIGHT,
        std.math.cast(i64, source.window_index) orelse return OMNI_ERR_OUT_OF_RANGE,
        -1,
        -1,
        -1,
    );
    if (rc != OMNI_OK) return rc;

    if (!same_column and source_column.window_count == 1) {
        rc = addMutationEdit(
            out_result,
            OMNI_NIRI_MUTATION_EDIT_REMOVE_COLUMN_IF_EMPTY,
            std.math.cast(i64, source.column_index) orelse return OMNI_ERR_OUT_OF_RANGE,
            -1,
            -1,
            -1,
        );
        if (rc != OMNI_OK) return rc;
    }

    if (same_column) {
        if (source_column.is_tabbed != 0) {
            const source_active_same = @min(source_column.active_tile_idx, source_column.window_count - 1);
            rc = addMutationEdit(
                out_result,
                OMNI_NIRI_MUTATION_EDIT_SET_ACTIVE_TILE,
                std.math.cast(i64, source.column_index) orelse return OMNI_ERR_OUT_OF_RANGE,
                -1,
                std.math.cast(i64, source_active_same) orelse return OMNI_ERR_OUT_OF_RANGE,
                -1,
            );
            if (rc != OMNI_OK) return rc;
        }
    } else if (source_column.window_count > 1) {
        const source_active = clampedActiveAfterRemoval(source_column);
        rc = addMutationEdit(
            out_result,
            OMNI_NIRI_MUTATION_EDIT_SET_ACTIVE_TILE,
            std.math.cast(i64, source.column_index) orelse return OMNI_ERR_OUT_OF_RANGE,
            -1,
            std.math.cast(i64, source_active) orelse return OMNI_ERR_OUT_OF_RANGE,
            -1,
        );
        if (rc != OMNI_OK) return rc;
    }

    if (target_column.is_tabbed != 0) {
        rc = addMutationEdit(
            out_result,
            OMNI_NIRI_MUTATION_EDIT_SET_ACTIVE_TILE,
            std.math.cast(i64, target.column_index) orelse return OMNI_ERR_OUT_OF_RANGE,
            -1,
            std.math.cast(i64, @min(target_column.active_tile_idx, target_column.window_count - 1)) orelse return OMNI_ERR_OUT_OF_RANGE,
            -1,
        );
        if (rc != OMNI_OK) return rc;
    }

    rc = setMutationTargetWindow(out_result, source.window_index);
    if (rc != OMNI_OK) return rc;
    out_result.applied = 1;
    return OMNI_OK;
}

pub fn omni_niri_mutation_plan_impl(
    columns: [*c]const OmniNiriStateColumnInput,
    column_count: usize,
    windows: [*c]const OmniNiriStateWindowInput,
    window_count: usize,
    request: [*c]const OmniNiriMutationRequest,
    out_result: [*c]OmniNiriMutationResult,
) i32 {
    if (request == null or out_result == null) return OMNI_ERR_INVALID_ARGS;
    if (column_count > 0 and columns == null) return OMNI_ERR_INVALID_ARGS;
    if (window_count > 0 and windows == null) return OMNI_ERR_INVALID_ARGS;

    var resolved_result: OmniNiriMutationResult = undefined;
    initMutationResult(&resolved_result);

    const req = request[0];

    var source: SelectedContext = undefined;
    const source_rc = parseWindowContextByIndex(
        columns,
        windows,
        column_count,
        window_count,
        req.source_window_index,
        &source,
    );
    if (source_rc != OMNI_OK) return source_rc;

    const rc: i32 = blk: {
        switch (req.op) {
            OMNI_NIRI_MUTATION_OP_MOVE_WINDOW_VERTICAL,
            OMNI_NIRI_MUTATION_OP_SWAP_WINDOW_VERTICAL,
            => break :blk planMoveWindowVertical(columns, source, req.direction, &resolved_result),
            OMNI_NIRI_MUTATION_OP_MOVE_WINDOW_HORIZONTAL => {
                const max_windows_per_column = std.math.cast(usize, req.max_windows_per_column) orelse break :blk OMNI_ERR_INVALID_ARGS;
                if (max_windows_per_column == 0) break :blk OMNI_ERR_INVALID_ARGS;
                break :blk planMoveWindowHorizontal(
                    columns,
                    column_count,
                    source,
                    req.direction,
                    req.infinite_loop != 0,
                    max_windows_per_column,
                    &resolved_result,
                );
            },
            OMNI_NIRI_MUTATION_OP_SWAP_WINDOW_HORIZONTAL => break :blk planSwapWindowHorizontal(
                columns,
                column_count,
                source,
                req.direction,
                req.infinite_loop != 0,
                &resolved_result,
            ),
            OMNI_NIRI_MUTATION_OP_SWAP_WINDOWS_BY_MOVE => {
                var target: SelectedContext = undefined;
                const target_rc = parseWindowContextByIndex(
                    columns,
                    windows,
                    column_count,
                    window_count,
                    req.target_window_index,
                    &target,
                );
                if (target_rc != OMNI_OK) break :blk target_rc;
                break :blk planSwapWindowsByMove(columns, source, target, &resolved_result);
            },
            OMNI_NIRI_MUTATION_OP_INSERT_WINDOW_BY_MOVE => {
                var target: SelectedContext = undefined;
                const target_rc = parseWindowContextByIndex(
                    columns,
                    windows,
                    column_count,
                    window_count,
                    req.target_window_index,
                    &target,
                );
                if (target_rc != OMNI_OK) break :blk target_rc;
                break :blk planInsertWindowByMove(
                    columns,
                    source,
                    target,
                    req.insert_position,
                    &resolved_result,
                );
            },
            else => break :blk OMNI_ERR_INVALID_ARGS,
        }
    };

    if (rc != OMNI_OK) return rc;

    out_result[0] = resolved_result;
    return OMNI_OK;
}
