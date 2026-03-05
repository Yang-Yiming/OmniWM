const abi = @import("abi_types.zig");
const layout_context = @import("layout_context.zig");

pub const OmniNiriRuntime = layout_context.OmniNiriLayoutContext;

pub fn omni_niri_runtime_create_impl() [*c]OmniNiriRuntime {
    return @ptrCast(layout_context.omni_niri_layout_context_create_impl());
}

pub fn omni_niri_runtime_destroy_impl(runtime: [*c]OmniNiriRuntime) void {
    layout_context.omni_niri_layout_context_destroy_impl(@ptrCast(runtime));
}

pub fn omni_niri_runtime_seed_impl(
    runtime: [*c]OmniNiriRuntime,
    request: [*c]const abi.OmniNiriRuntimeSeedRequest,
) i32 {
    if (request == null) return abi.OMNI_ERR_INVALID_ARGS;
    return layout_context.omni_niri_ctx_seed_runtime_state_impl(
        @ptrCast(runtime),
        request[0].columns,
        request[0].column_count,
        request[0].windows,
        request[0].window_count,
    );
}

pub fn omni_niri_runtime_apply_command_impl(
    source_runtime: [*c]OmniNiriRuntime,
    target_runtime: [*c]OmniNiriRuntime,
    request: [*c]const abi.OmniNiriRuntimeCommandRequest,
    out_result: [*c]abi.OmniNiriRuntimeCommandResult,
) i32 {
    if (request == null or out_result == null) return abi.OMNI_ERR_INVALID_ARGS;

    var txn_result: abi.OmniNiriTxnResult = undefined;
    const rc = layout_context.omni_niri_ctx_apply_txn_impl(
        @ptrCast(source_runtime),
        @ptrCast(target_runtime),
        &request[0].txn,
        &txn_result,
    );
    out_result[0] = .{ .txn = txn_result };
    return rc;
}

pub fn omni_niri_runtime_render_impl(
    runtime: [*c]OmniNiriRuntime,
    layout: [*c]layout_context.OmniNiriLayoutContext,
    request: [*c]const abi.OmniNiriRuntimeRenderRequest,
    out_output: [*c]abi.OmniNiriRuntimeRenderOutput,
) i32 {
    if (runtime == null or request == null or out_output == null) return abi.OMNI_ERR_INVALID_ARGS;

    const runtime_ctx: *const OmniNiriRuntime = @ptrCast(&runtime[0]);
    const render_ctx: [*c]layout_context.OmniNiriLayoutContext = if (layout != null) layout else @ptrCast(runtime);

    if (request[0].column_count != runtime_ctx.runtime_column_count or
        request[0].window_count != runtime_ctx.runtime_window_count)
    {
        return abi.OMNI_ERR_OUT_OF_RANGE;
    }

    return layout_context.omni_niri_layout_pass_v3_impl(
        render_ctx,
        request[0].columns,
        request[0].column_count,
        request[0].windows,
        request[0].window_count,
        request[0].working_x,
        request[0].working_y,
        request[0].working_width,
        request[0].working_height,
        request[0].view_x,
        request[0].view_y,
        request[0].view_width,
        request[0].view_height,
        request[0].fullscreen_x,
        request[0].fullscreen_y,
        request[0].fullscreen_width,
        request[0].fullscreen_height,
        request[0].primary_gap,
        request[0].secondary_gap,
        request[0].view_start,
        request[0].viewport_span,
        request[0].workspace_offset,
        request[0].scale,
        request[0].orientation,
        out_output[0].windows,
        out_output[0].window_count,
        out_output[0].columns,
        out_output[0].column_count,
    );
}

pub fn omni_niri_runtime_snapshot_impl(
    runtime: [*c]const OmniNiriRuntime,
    out_export: [*c]abi.OmniNiriRuntimeStateExport,
) i32 {
    return layout_context.omni_niri_ctx_export_runtime_state_impl(
        @ptrCast(runtime),
        out_export,
    );
}
