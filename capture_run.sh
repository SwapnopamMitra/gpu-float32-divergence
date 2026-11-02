#!/usr/bin/env bash
set -euo pipefail

NODE_LABEL="$1"; shift
INPUT_FILE="$1"; shift

ARTIFACT_FILE=""
if [ "${1:-}" = "--artifact" ]; then
    shift
    ARTIFACT_FILE="$1"; shift
fi

if [ "${1:-}" != "--" ]; then
    echo "expected -- before command (or --artifact <file> -- before command)" >&2
    exit 1
fi
shift
CMD=("$@")

STDOUT_FILE="output_${NODE_LABEL}.stdout"
STDERR_FILE="output_${NODE_LABEL}.stderr"
MANIFEST="manifest_${NODE_LABEL}.json"

# Environment fingerprint
KERNEL=$(uname -srmo 2>/dev/null || uname -a)
CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//' || echo "unknown")
CPU_FLAGS_HASH=$(grep -m1 "^flags" /proc/cpuinfo 2>/dev/null | sha256sum | cut -d' ' -f1 || echo "unknown")
GLIBC_VER=$(ldd --version 2>/dev/null | head -1 || echo "unknown")

# Binary hash
BIN_PATH=$(command -v "${CMD[0]}" || echo "")
if [ -n "$BIN_PATH" ] && [ -f "$BIN_PATH" ]; then
    BIN_HASH=$(sha256sum "$BIN_PATH" | cut -d' ' -f1)
else
    BIN_HASH="unresolved:${CMD[0]}"
fi

# Input hash
if [ -f "$INPUT_FILE" ]; then
    INPUT_HASH=$(sha256sum "$INPUT_FILE" | cut -d' ' -f1)
else
    INPUT_HASH="MISSING"
fi

# Clear stale artifacts
if [ -n "$ARTIFACT_FILE" ] && [ -f "$ARTIFACT_FILE" ]; then
    rm -f "$ARTIFACT_FILE"
fi

# Run
START=$(date +%s.%N)
"${CMD[@]}" > "$STDOUT_FILE" 2> "$STDERR_FILE" || true
END=$(date +%s.%N)
ELAPSED=$(echo "$END - $START" | bc 2>/dev/null || echo "unknown")

STDOUT_HASH=$(sha256sum "$STDOUT_FILE" | cut -d' ' -f1)

# Resolve result
if [ -n "$ARTIFACT_FILE" ]; then
    if [ ! -f "$ARTIFACT_FILE" ]; then
        echo "ERROR: --artifact ${ARTIFACT_FILE} was specified but not produced." >&2
        exit 1
    fi
    ARTIFACT_COPY="artifact_${NODE_LABEL}_$(basename "$ARTIFACT_FILE")"
    cp "$ARTIFACT_FILE" "$ARTIFACT_COPY"
    RESULT_FILE="$ARTIFACT_COPY"
    RESULT_HASH=$(sha256sum "$ARTIFACT_COPY" | cut -d' ' -f1)
    RESULT_KIND="artifact_file"
else
    RESULT_FILE="$STDOUT_FILE"
    RESULT_HASH="$STDOUT_HASH"
    RESULT_KIND="stdout"
fi

# GPU info
GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "")
CUDA_VER=$(nvcc --version 2>/dev/null | grep release | sed 's/.*release //' | cut -d, -f1 || echo "")

cat > "$MANIFEST" <<EOF
{
  "node_label": "${NODE_LABEL}",
  "timestamp_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "kernel": "${KERNEL}",
  "cpu_model": "${CPU_MODEL}",
  "cpu_flags_hash": "${CPU_FLAGS_HASH}",
  "glibc_version": "$(echo "$GLIBC_VER" | head -1)",
  "gpu_model": "${GPU_MODEL}",
  "cuda_version": "${CUDA_VER}",
  "command": "$(printf '%s ' "${CMD[@]}")",
  "binary_path": "${BIN_PATH}",
  "binary_sha256": "${BIN_HASH}",
  "input_file": "${INPUT_FILE}",
  "input_sha256": "${INPUT_HASH}",
  "elapsed_seconds": "${ELAPSED}",
  "result_kind": "${RESULT_KIND}",
  "result_file": "${RESULT_FILE}",
  "raw_output_sha256": "${RESULT_HASH}",
  "stdout_file": "${STDOUT_FILE}",
  "stdout_sha256": "${STDOUT_HASH}"
}
EOF

echo "wrote ${MANIFEST}"
