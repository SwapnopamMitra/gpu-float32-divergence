#!/bin/bash

set -euo pipefail

INPUT="${1:-test.bin}"
OUTDIR="${2:-output}"

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
done
./bin/reduction_tree "$INPUT" "$OUTDIR/reduction_tree.bin" >/dev/null

UNIQUE_HASHES=$(for i in $(seq 1 10); do
    sha256sum "$OUTDIR/reduction_run_$i.bin" | cut -d' ' -f1
done | sort -u | wc -l)

echo "  Tree reduction:   $(sha256sum "$OUTDIR/reduction_tree.bin" | cut -d' ' -f1)"
echo "  Atomic (10 runs): $UNIQUE_HASHES unique hash(es)"
echo ""

echo "=== Summary ==="
[ "$HASH_FMA_ON" != "$HASH_FMA_OFF" ] && echo "FMA vs non-FMA:    DIVERGENCE" || echo "FMA vs non-FMA:    no divergence"
[ "$HASH_FAST_ON" != "$HASH_FAST_OFF" ] && echo "Fast vs accurate:  DIVERGENCE" || echo "Fast vs accurate:  no divergence"
[ "$UNIQUE_HASHES" -gt 1 ] && echo "Reduction order:   DIVERGENCE ($UNIQUE_HASHES unique)" || echo "Reduction order:   no divergence ($UNIQUE_HASHES unique)"
echo ""
echo "Outputs written to: $OUTDIR/"
