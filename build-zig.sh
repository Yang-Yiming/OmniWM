#!/usr/bin/env bash
# build-zig.sh — compile zig/omni_layout.zig into .build/zig/libomni_layout.a
#
# Default behavior builds a universal macOS static library (arm64 + x86_64).
# Set ZIG_TARGET to produce a single-arch library:
#   ZIG_TARGET=x86_64-macos ./build-zig.sh
set -euo pipefail

OUT_DIR=".build/zig"
OUT_LIB="${OUT_DIR}/libomni_layout.a"
SRC="zig/omni_layout.zig"
REQUESTED_TARGET="${ZIG_TARGET:-}"
REQUIRED_SYMBOLS=(
    "omni_niri_ctx_apply_txn"
    "omni_niri_ctx_export_delta"
    "omni_border_runtime_create"
    "omni_border_runtime_destroy"
    "omni_border_runtime_apply_config"
    "omni_border_runtime_apply_presentation"
    "omni_border_runtime_submit_snapshot"
    "omni_border_runtime_invalidate_displays"
    "omni_border_runtime_hide"
)

if ! command -v zig >/dev/null 2>&1; then
    echo "error: zig not found in PATH — install from https://ziglang.org/download/" >&2
    exit 1
fi

resolve_sdk_path() {
    local sdk_path=""

    if command -v xcrun >/dev/null 2>&1; then
        sdk_path="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
        if [[ -z "${sdk_path}" ]]; then
            echo "error: xcrun could not determine the macOS SDK path" >&2
            exit 1
        fi
    else
        local sdkroot_candidate="${SDKROOT:-}"
        if [[ -z "${sdkroot_candidate}" ]]; then
            echo "error: xcrun is unavailable and SDKROOT is not set" >&2
            exit 1
        fi
        sdk_path="$(realpath "${sdkroot_candidate}" 2>/dev/null || true)"
        if [[ -z "${sdk_path}" ]]; then
            echo "error: SDKROOT could not be resolved: ${sdkroot_candidate}" >&2
            exit 1
        fi
        case "${sdk_path}" in
            /Applications/*.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/*|/Library/Developer/CommandLineTools/SDKs/*)
                ;;
            *)
                echo "error: SDKROOT must resolve inside Xcode or CommandLineTools SDK roots: ${sdk_path}" >&2
                exit 1
                ;;
        esac
    fi

    printf '%s\n' "${sdk_path}"
}

verify_required_symbols() {
    local artifact="$1"
    local label="$2"
    local symbol_names

    symbol_names="$(nm "${artifact}" 2>/dev/null | awk '{ name = $NF; sub(/^_/, "", name); print name }')"
    if [[ -z "${symbol_names}" ]]; then
        echo "error: unable to inspect symbols in ${artifact}" >&2
        exit 1
    fi

    local missing=0
    local symbol
    for symbol in "${REQUIRED_SYMBOLS[@]}"; do
        if ! grep -Fxq "${symbol}" <<< "${symbol_names}"; then
            echo "error: missing required symbol '${symbol}' in ${label} (${artifact})" >&2
            missing=1
        fi
    done

    if [[ "${missing}" -ne 0 ]]; then
        exit 1
    fi

    echo "Verified ${label} exports required layout and border symbols."
}

SDK_PATH="$(resolve_sdk_path)"

build_one() {
    local target="$1"
    local output="$2"
    echo "▸ zig build-lib  target=${target}  out=${output}"
    zig build-lib \
        -O ReleaseFast \
        -target "${target}" \
        --sysroot "${SDK_PATH}" \
        -F"${SDK_PATH}/System/Library/Frameworks" \
        -femit-bin="${output}" \
        -fno-emit-h \
        "${SRC}"
}

mkdir -p "${OUT_DIR}"

if [[ -n "${REQUESTED_TARGET}" ]]; then
    build_one "${REQUESTED_TARGET}" "${OUT_LIB}"
    verify_required_symbols "${OUT_LIB}" "Zig archive"
    if command -v lipo >/dev/null 2>&1; then
        lipo -info "${OUT_LIB}"
    fi
    echo "✓ ${OUT_LIB}"
    exit 0
fi

if ! command -v lipo >/dev/null 2>&1; then
    echo "error: lipo is required to create a universal macOS static library" >&2
    exit 1
fi

ARM64_LIB="${OUT_DIR}/libomni_layout_arm64.a"
X86_64_LIB="${OUT_DIR}/libomni_layout_x86_64.a"

build_one "aarch64-macos" "${ARM64_LIB}"
build_one "x86_64-macos" "${X86_64_LIB}"

echo "▸ lipo create  out=${OUT_LIB}"
lipo -create -output "${OUT_LIB}" "${ARM64_LIB}" "${X86_64_LIB}"
verify_required_symbols "${OUT_LIB}" "Zig archive"
lipo -info "${OUT_LIB}"

echo "✓ ${OUT_LIB}"
