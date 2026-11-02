# divergence-verifier

Independent harness for reproducing output divergence in float32 computation across commodity hardware.

> **Correction Notice (November 2, 2026)**
>
> An earlier version of the CPU harness (`divergence_demo.sh`) in this repository was missing the `gcc` compilation step. It executed the Python generation and terminal printing, but it did not execute the compiled float32 C math.
>
> The script was fixed and the test was rerun across glibc 2.31 (Ubuntu 20.04), 2.35 (Ubuntu 22.04), and 2.39 (Ubuntu 24.04) on the same Intel i5 host. The output was identical on all three (`b73b2b34...`). **The CPU divergence claim is retracted.** The C math for this specific dataset is stable across these glibc environments.
>
> The historical CPU manifests remain in the `historical/` directory for record only. The divergence they showed was likely caused by the harness fault, not hardware.
>
> The GPU findings below were reproduced across three machines. The manifests are in `cuda/manifests/`.

---

## Table of Contents

- [What this is](#what-this-is)
- [What this is not](#what-this-is-not)
- [Repository contents](#repository-contents)
- [GPU finding](#gpu-finding)
- [Reproducing the GPU test](#reproducing-the-gpu-test)
- [Sample output](#sample-output-gpu)
- [Design constraints](#design-constraints)
- [Adding nodes](#adding-nodes)
- [License](#license)

---

## What this is

A capture-and-compare harness plus a set of manifests recording divergence findings on real hardware.

**GPU finding: path-dependent and scheduling-dependent divergence.**
Three machines (two Google Colab Tesla T4 instances, one local RTX 3050), six kernels. The four deterministic kernels (FMA on/off, fast-math on/off) produce identical output across GPUs. Different execution paths on the same GPU produce different output. At 1,000,000 elements, atomic reduction is non-deterministic from run to run. Tree reduction was deterministic in all current runs; an earlier, unreproduced observation is described under [GPU finding](#gpu-finding).

Same source. Same input. Different execution path or scheduling produces different output. The manifests are the record. The scripts reproduce the conditions.

---

## What this is not

This repository does not contain, reference, or depend upon any canonicalization method, any external tool, or any resolution logic. If canonical hashes or tool-specific outputs appear in other published material, that is where they belong, not here.

No canonicalization logic, no SPCMP reference, and no resolution method appears in this repository. If canonical hashes appear in other material, they are not derived from anything here.

The GPU harness uses only standard CUDA intrinsics and compiler flags. It does not depend on any particular SDK version, driver, or architecture beyond what the Makefile declares.

---

## Repository contents

```text
divergence-verifier/
├── README.md
├── LICENSE
├── capture_run.sh                  # fingerprints binary + input + output, writes manifest
│
├── historical/                     # Retracted CPU claim (retained for record only)
│   ├── divergence_demo.sh
│   ├── run_divergence_test.sh
│   ├── compare_runs.py
│   ├── retraction_results.json
│   └── manifest_*.json             # The original invalid manifests
│
└── cuda/                           # GPU divergence harness
    ├── Makefile                    # fat binary build (sm_75 + sm_86)
    ├── kernels/
    │   ├── fma_vs_no_fma.cu
    │   ├── fast_vs_accurate.cu
    │   └── reduction_order.cu
    ├── divergence_demo_cuda.sh
    ├── compare_cuda_runs.py
    ├── run_cuda_divergence_test.sh
    ├── build_fat_bundle.sh         # bundle for cross-machine transfer
    ├── big_test.bin                # GPU corpus (1,000,000 elements): default
    ├── atomic_hashes.txt           # 10 runs of reduction_atomic on Prime (RTX 3050): 9 unique
    ├── colab_atomic_hashes.txt     # 10 runs of reduction_atomic on Colab (Tesla T4): 10 unique
    ├── tree_hashes.txt             # 10 runs of reduction_tree on Prime (RTX 3050): 1 unique
    ├── tree_invocations.txt        # tree hash from 10 separate script invocations: 1 unique
    └── manifests/
        ├── manifest_Colab_gpu1_fast_off.json
        ├── manifest_Colab_gpu1_fast_on.json
        ├── manifest_Colab_gpu1_fma_off.json
        ├── manifest_Colab_gpu1_fma_on.json
        ├── manifest_Colab_gpu1_red_atomic.json
        ├── manifest_Colab_gpu1_red_tree.json
        ├── manifest_Colab_gpu2_fast_off.json
        ├── manifest_Colab_gpu2_fast_on.json
        ├── manifest_Colab_gpu2_fma_off.json
        ├── manifest_Colab_gpu2_fma_on.json
        ├── manifest_Colab_gpu2_red_atomic.json
        ├── manifest_Colab_gpu2_red_tree.json
        ├── manifest_Prime_gpu_fast_off.json
        ├── manifest_Prime_gpu_fast_on.json
        ├── manifest_Prime_gpu_fma_off.json
        ├── manifest_Prime_gpu_fma_on.json
        ├── manifest_Prime_gpu_red_atomic.json
        └── manifest_Prime_gpu_red_tree.json
```

---

## GPU finding

Three machines: two Google Colab Tesla T4 instances and one local RTX 3050. Six kernels. Same source code and compiler flags, compiled independently on each machine (binary hashes differ per machine). Same input (1,000,000 elements).

| Kernel | nvcc flags | Tesla T4 (sm_75, CUDA 13.0) | RTX 3050 (sm_86, CUDA 13.0) |
|--------|------------|-----------------------------|-----------------------------|
| `fma_default` | `-O2 fat -DUSE_FMA` | `5b4f9db9...` | `5b4f9db9...` |
| `fma_no_fma` | `-O2 fat --fmad=false` | `80d7301c...` | `80d7301c...` |
| `fast_on` | `-O2 fat -DUSE_FAST` | `743d2d5f...` | `743d2d5f...` |
| `fast_off` | `-O2 fat` | `cbe5cea0...` | `cbe5cea0...` |
| `reduction_tree` | `fat -DTREE_REDUCTION` | `37d5c6b3...` | `37d5c6b3...` (100 of 100 runs) |
| `reduction_atomic` | `fat -DATOMIC_REDUCTION` | 10 unique / 10 runs (`colab_atomic_hashes.txt`, host fcd2464a08ac) | 9 unique / 10 runs (`atomic_hashes.txt`, Prime) |

### Deterministic kernels

For `fma_default`, `fma_no_fma`, `fast_on` and `fast_off`, the output hash is bit-identical across Turing (T4) and Ampere (RTX 3050), despite the binaries being compiled separately on each machine.

### Execution path

On the same GPU, the FMA and fast-math kernels produce different hashes when the compiler flags change.

### Atomic reduction

Non-deterministic at 1,000,000 elements. On the RTX 3050, 10 runs produced 9 unique hashes (`cuda/atomic_hashes.txt`). On the Tesla T4, 10 runs produced 10 unique hashes (`cuda/colab_atomic_hashes.txt`).

The 10-run atomic test on Colab was run on host `fcd2464a08ac` on November 3, 2026 (IST; the host clock header in the hashes file reads November 2, 2026, UTC). The other T4 instance (`gpu2`) only contributed manifests for the deterministic kernels and a single atomic run.

### Tree reduction

On the RTX 3050, 10 runs in one invocation (`cuda/tree_hashes.txt`) and 10 separate invocations (`cuda/tree_invocations.txt`) all produced `37d5c6b3...`. `compute-sanitizer` initcheck and racecheck report no errors or hazards for `reduction_tree`. The committed manifests for all three machines record `37d5c6b3...`.

### Unreproduced observation

In earlier terminal logs, produced with earlier versions of the demo script and kernel, `reduction_tree` was seen to produce a second hash, `d8566645...`, on both Prime and a Colab T4. This has not been reproduced with the current script and kernel, and is not recorded in any committed file. The cause is not established.

### Fast-math note

`fast_on` and `fast_off` compare the fast intrinsic `__expf` against the accurate library function `expf`. These differ in both polynomial approximation and FTZ behavior. The label reflects the fast-math path, not an isolated FTZ toggle.

### Manifest provenance

The 18 committed manifests were generated by an earlier version of the demo script, which ran the tree kernel once after the atomic loop. The current script runs 10 iterations of both kernels.

### Conclusion

The divergence source on GPU is the execution path (FMA vs non-FMA, fast intrinsic vs accurate library) and the scheduling of non-associative operations (atomic reduction), not the GPU architecture itself.

### Corpus

The corpus is `big_test.bin`. Its SHA256 is:

```text
606718c45400af4047e4a2cb9f1e2ba31d688f2aa19fbd2ff6f6a8d2ea1634e7
```

---

## Reproducing the GPU test

### 1. Verify the corpus

The corpus is committed under `cuda/` as `big_test.bin`. Verify it:

```bash
cd cuda
sha256sum big_test.bin
```

Expected output:

```text
606718c45400af4047e4a2cb9f1e2ba31d688f2aa19fbd2ff6f6a8d2ea1634e7  big_test.bin
```

### 2. Build fat binaries

```bash
cd cuda
make all
```

### 3. Run on each GPU machine

```bash
./run_cuda_divergence_test.sh
```

This script uses `big_test.bin` by default. Published results used independent per-machine builds. `build_fat_bundle.sh` is an alternative: it produces `cuda_bundle_<timestamp>.tar.gz` for transferring prebuilt binaries to a target machine.

### 4. Compare across machines

Copy all `manifest_*.json` files into `cuda/manifests/` and run from `cuda/`:

```bash
cd cuda
python3 compare_cuda_runs.py
```

---

## Sample output (GPU)

```text
$ python3 compare_cuda_runs.py

Loaded 18 GPU manifests:

  [Colab_gpu1_fma_on]
    gpu          : Tesla T4
    cuda         : 13.0
    kernel       : fma_default
    output_hash  : 5b4f9db9a65ceccc...

  [Prime_gpu_fma_on]
    gpu          : NVIDIA GeForce RTX 3050 6GB Laptop GPU
    cuda         : 13.0
    kernel       : fma_default
    output_hash  : 5b4f9db9a65ceccc...

  ... (18 manifests total)

Input identical: CONFIRMED

WARNING: Same kernel 'reduction_atomic' produced different output across machines.
RESULT: CUDA DIVERGENCE -- GENUINE FINDING
Same input, different compile flags -> different output.
```

The `reduction_atomic` warning compares one run per machine of a non-deterministic kernel. It is not evidence of a machine-dependent difference.

---

## Design constraints

- `capture_run.sh` hashes the executable on disk, hashes the input file before the run, clears any stale artifact before executing, and writes a timestamped JSON manifest. It does not modify or canonicalize output.
- `cuda/Makefile` builds fat binaries for cross-architecture testing. For the four deterministic kernels, the same source and compiler flags produce bit-identical output on both Turing and Ampere GPUs.
- `cuda/compare_cuda_runs.py` groups manifests by kernel identity and verifies that all nodes used identical input.

---

## Adding nodes

1. Run `run_cuda_divergence_test.sh` on the new GPU machine.
2. Copy the resulting `cuda/manifests/manifest_*.json` into `cuda/manifests/`.
3. Re-run `compare_cuda_runs.py` from `cuda/`.

Hardware diversity is the point. Different GPU families (Turing vs Ampere) are covered. Ada, Hopper and non-NVIDIA GPUs are not.

---

## License

MIT. The harness only. The test corpus (`big_test.bin`) is committed as data and carries no separate rights.