#!/bin/bash
set -e

echo "=== CUDA Divergence Test ==="
echo ""

if [ ! -f bin/fma_default ]; then
    echo "No pre-built binaries found, building..."
    make all
else
    echo "Using pre-built binaries (transfer mode)."
    echo ""
    echo "Binary hashes for verification:"
    for b in bin/*; do
        [ -f "$b" ] && printf "  %-40s %s\n" "$b" "$(sha256sum "$b" | cut -d' ' -f1)"
    done
    echo ""
fi

if [ ! -f big_test.bin ]; then
    if [ -f ../big_test.bin ]; then
        cp ../big_test.bin big_test.bin
    else
        echo "ERROR: big_test.bin not found."
        exit 1
    fi
fi

./divergence_demo_cuda.sh big_test.bin output_big

echo ""
echo "=== Building manifests ==="
echo ""

NODE_LABEL=$(hostname | tr -d '.-')
mkdir -p manifests

INPUT_HASH=$(sha256sum big_test.bin | cut -d' ' -f1)
GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
CUDA_VER=$(nvcc --version 2>/dev/null | grep release | sed 's/.*release //' | cut -d, -f1 || echo "unknown")
COMPUTE_CAP=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 || echo "unknown")
DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)

emit_manifest() {
    local label="$1"
    local kernel_name="$2"
    local flags="$3"
    local outfile="$4"
    local binname=""
    local binhash=""
    local outhash=""

    case "$kernel_name" in
        fma_on)  binname="fma_default" ;;
        fma_off) binname="fma_no_fma" ;;
        fast_on)  binname="fast_on" ;;
        fast_off) binname="fast_off" ;;
        red_tree)   binname="reduction_tree" ;;
        red_atomic) binname="reduction_atomic" ;;
    esac

    if [ -f "bin/$binname" ]; then
        binhash=$(sha256sum "bin/$binname" | cut -d' ' -f1)
    fi
    if [ -f "$outfile" ]; then
        outhash=$(sha256sum "$outfile" | cut -d' ' -f1)
    fi

    cat > "manifests/manifest_${label}.json" <<EOF
{
  "node_label": "${NODE_LABEL}_${label}",
  "gpu_model": "${GPU_MODEL}",
  "compute_capability": "${COMPUTE_CAP}",
  "driver_version": "${DRIVER_VER}",
  "cuda_version": "${CUDA_VER}",
  "kernel": "${kernel_name}",
  "binary_name": "${binname}",
  "binary_sha256": "${binhash}",
  "nvcc_flags": "${flags}",
  "input_file": "big_test.bin",
  "input_sha256": "${INPUT_HASH}",
  "result_file": "${outfile}",
  "raw_output_sha256": "${outhash}"
}
EOF
}

emit_manifest "gpu_fma_on"  "fma_on"  "-O2 fat -DUSE_FMA"     "output_big/fma_on.bin"
emit_manifest "gpu_fma_off" "fma_off" "-O2 fat --fmad=false" "output_big/fma_off.bin"
emit_manifest "gpu_fast_on" "fast_on" "-O2 fat -DUSE_FAST"    "output_big/fast_on.bin"
emit_manifest "gpu_fast_off" "fast_off" "-O2 fat"             "output_big/fast_off.bin"
emit_manifest "gpu_red_tree"   "red_tree"   "fat -DTREE_REDUCTION"   "output_big/reduction_tree.bin"
emit_manifest "gpu_red_atomic" "red_atomic" "fat -DATOMIC_REDUCTION" "output_big/reduction_run_1.bin"

echo "=== Manifests written ==="
ls -la manifests/

echo ""
echo "=== Local self-comparison ==="
python3 compare_cuda_runs.py || true