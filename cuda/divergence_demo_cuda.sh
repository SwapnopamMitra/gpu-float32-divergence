#!/bin/bash

set -euo pipefail

INPUT="${1:-big_test.bin}"
OUTDIR="${2:-output_big}"

mkdir -p "$OUTDIR"

echo "=== CUDA Divergence Capture ==="
echo "Node: $(hostname)"
echo "GPU:  $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"
echo "CUDA: $(nvcc --version 2>/dev/null | grep release | sed 's/.*release //' | cut -d, -f1 || echo unknown)"
echo "Input: $INPUT"
echo ""

if [ ! -f "$INPUT" ]; then
    echo "ERROR: $INPUT not found."
    exit 1
fi

# --- FMA ---
echo "[1/3] FMA vs no-FMA..."
./bin/fma_default "$INPUT" "$OUTDIR/fma_on.bin"  >/dev/null
./bin/fma_no_fma  "$INPUT" "$OUTDIR/fma_off.bin" >/dev/null
HASH_FMA_ON=$(sha256sum  "$OUTDIR/fma_on.bin"  | cut -d' ' -f1)
HASH_FMA_OFF=$(sha256sum "$OUTDIR/fma_off.bin" | cut -d' ' -f1)
echo "  FMA on : $HASH_FMA_ON"
echo "  FMA off: $HASH_FMA_OFF"
echo ""

# --- Fast vs Accurate ---
echo "[2/3] Fast intrinsic vs accurate library..."
./bin/fast_on  "$INPUT" "$OUTDIR/fast_on.bin"  >/dev/null
./bin/fast_off "$INPUT" "$OUTDIR/fast_off.bin" >/dev/null
HASH_FAST_ON=$(sha256sum  "$OUTDIR/fast_on.bin"  | cut -d' ' -f1)
HASH_FAST_OFF=$(sha256sum "$OUTDIR/fast_off.bin" | cut -d' ' -f1)
echo "  Fast on : $HASH_FAST_ON"
echo "  Fast off: $HASH_FAST_OFF"
echo ""

# --- Reduction ---
echo "[3/3] Reduction order (10 runs)..."
for i in $(seq 1 10); do
    ./bin/reduction_atomic "$INPUT" "$OUTDIR/reduction_run_$i.bin" >/dev/null
    ./bin/reduction_tree   "$INPUT" "$OUTDIR/tree_run_$i.bin"      >/dev/null
done

sha256sum "$OUTDIR"/reduction_run_*.bin > "$OUTDIR/atomic_hashes.txt"
sha256sum "$OUTDIR"/tree_run_*.bin      > "$OUTDIR/tree_hashes.txt"

ATOMIC_UNIQUE=$(cut -d' ' -f1 "$OUTDIR/atomic_hashes.txt" | sort -u | wc -l)
TREE_UNIQUE=$(cut -d' ' -f1 "$OUTDIR/tree_hashes.txt" | sort -u | wc -l)

echo "  Tree reduction:   $TREE_UNIQUE unique hashes / 10 runs"
echo "  Atomic reduction: $ATOMIC_UNIQUE unique hashes / 10 runs"
echo ""

echo "=== Summary ==="

if [ "$HASH_FMA_ON" != "$HASH_FMA_OFF" ]; then
    echo "FMA vs non-FMA:    DIVERGENCE"
else
    echo "FMA vs non-FMA:    no divergence"
fi

if [ "$HASH_FAST_ON" != "$HASH_FAST_OFF" ]; then
    echo "Fast vs accurate:  DIVERGENCE"
else
    echo "Fast vs accurate:  no divergence"
fi

if [ "$ATOMIC_UNIQUE" -gt 1 ]; then
    echo "Atomic reduction:  NON-DETERMINISTIC ($ATOMIC_UNIQUE unique hashes)"
else
    echo "Atomic reduction:  deterministic ($ATOMIC_UNIQUE unique hash)"
fi

if [ "$TREE_UNIQUE" -gt 1 ]; then
    echo "Tree reduction:    NON-DETERMINISTIC ($TREE_UNIQUE unique hashes)"
else
    echo "Tree reduction:    deterministic ($TREE_UNIQUE unique hash)"
fi

echo ""
echo "Outputs written to: $OUTDIR/"