# divergence-verifier

Independent harness for reproducing output divergence in float32 computation
across commodity hardware, on both CPU and GPU execution paths.

This repository contains the harness and the captured manifests. It contains
nothing about how divergence is resolved or whether resolution is possible.

---

## What this is

A capture-and-compare harness plus a set of manifests recording real
divergence findings on real hardware.

The manifests record two independent findings:

**CPU finding -- environment-dependent divergence.**
Six distinct CPU configurations, same binary hash, same input hash,
**six different output hashes**. Notably, the two nodes running the same
AMD EPYC 7B13 produce different hashes (due to differing glibc versions).
Neither the CPU model nor the OS alone predicts the result.

**GPU finding -- path-dependent divergence.**
Two GPU architectures (Tesla T4 sm_75, RTX 3050 sm_86), six different
kernels. Same kernel across GPUs produces identical output. Different
kernels on the same GPU produce different output.

Same program. Same input. Different execution → different output.
The manifests are the record. The scripts reproduce the conditions.

---

## What this is not

This repository does not contain, reference, or depend upon any
canonicalization method, any external tool, or any resolution logic.
If canonical hashes or tool-specific outputs appear in other published
material, that is where they belong -- not here.

No canonicalization logic, no SPCMP reference, no resolution method
appears in this repository. If canonical hashes appear in other
material, they are not derived from anything here.

The GPU harness uses only standard CUDA intrinsics and compiler flags.
It does not depend on any particular SDK version, driver, or architecture
beyond what the Makefile declares.

---

## Repository contents

```
divergence-verifier/
├── README.md
├── LICENSE
├── capture_run.sh                  -- fingerprints binary + input + output, writes manifest
├── compare_runs.py                 -- collects CPU manifests, classifies the result
├── test.bin                        -- CPU divergence corpus
├── divergence_demo.sh              -- CPU divergence trigger
├── run_divergence_test.sh          -- one-command CPU runner
│
├── manifest_0e4e583760c2.json      -- CPU manifests (root directory)
├── manifest_6e258a114c61.json
├── manifest_Prime.json
├── manifest_c2e68d2ae4f6.json
├── manifest_project40c8f81744b8444da370e811d81e6c86.json
├── manifest_second_pc.json
│
└── cuda/                           -- GPU divergence harness
    ├── Makefile                    -- fat binary build (sm_75 + sm_86)
    ├── kernels/
    │   ├── fma_vs_no_fma.cu
    │   ├── fast_vs_accurate.cu     -- (renamed from ftz_subnormal.cu)
    │   └── reduction_order.cu
    ├── divergence_demo_cuda.sh
    ├── compare_cuda_runs.py
    ├── run_cuda_divergence_test.sh
    ├── build_fat_bundle.sh         -- bundle for cross-machine transfer
    ├── test.bin                    -- GPU divergence corpus
    └── manifests/
        ├── manifest_gpu_fma_on_rtx3050.json
        ├── manifest_gpu_fma_on_t4.json
        ├── manifest_gpu_fma_off_rtx3050.json
        ├── manifest_gpu_fma_off_t4.json
        ├── manifest_gpu_ftz_on_rtx3050.json
        ├── manifest_gpu_ftz_on_t4.json
        ├── manifest_gpu_ftz_off_rtx3050.json
        ├── manifest_gpu_ftz_off_t4.json
        ├── manifest_gpu_red_tree_rtx3050.json
        ├── manifest_gpu_red_tree_t4.json
        ├── manifest_gpu_red_atomic_rtx3050.json
        └── manifest_gpu_red_atomic_t4.json
```

Note: CPU manifests sit at the repository root, not in a subdirectory.
`compare_runs.py` scans the current working directory for
`manifest_*.json`, so the CPU comparison is run from the repository root.

---

## Scope

This repository is an independent verifier. It records what happened
and lets anyone reproduce the conditions. It does not diagnose the
cause, propose a fix, or depend on any particular hardware, driver,
or library version beyond what each manifest records.

The CPU manifests record an environment-dependent divergence finding.
The GPU manifests record a path-dependent divergence finding. These
are separate findings with separate causes and should be cited
separately.

---

## CPU finding

Six nodes. Six different environment configurations. Same binary, same input.

| Node | CPU | glibc | Output hash |
|------|-----|-------|-------------|
| Prime | Intel i5-12450HX | 2.39 | `b266807160a9ee69...` |
| 0e4e583760c2 | Intel Xeon @ 2.20GHz | 2.39 | `8f172ee242809dbf...` |
| 6e258a114c61 | Intel Xeon @ 2.00GHz | -- | `7989a6b20cc566cd...` |
| c2e68d2ae4f6 | AMD EPYC 7B13 | 2.35 | `44b36c0f3a01cc59...` |
| project40c8... | AMD EPYC 7B13 | -- | `a1b49047410b2620...` |
| second_pc | Intel i5-1255U | -- | `689c2e49eb09ec8b...` |

**Binary hash: identical across all six nodes** (`71cba87046d06afb...`).
**Input hash: identical across all six nodes** (`e851cab68f6e2350...`).
**Output hash: six distinct values.**

The two EPYC nodes differ across glibc versions, and every pair of nodes
sharing a glibc version also differs. Neither the CPU nor the glibc
version alone explains the result.

---

## GPU finding

Two GPUs. Six kernels. Same binary per kernel, same input.

| Kernel | nvcc flags | Tesla T4 (sm_75, CUDA 12.8) | RTX 3050 (sm_86, CUDA 13.0) |
|--------|------------|-----------------------------|-----------------------------|
| `fma_on` | `-O2 fat -DUSE_FMA` | `9abc1b84...` | `9abc1b84...` |
| `fma_off` | `-O2 fat --fmad=false` | `c0d12da3...` | `c0d12da3...` |
| `fast_on` | `-O2 fat -DUSE_FAST` | `8a792baa...` | `8a792baa...` |
| `fast_off` | `-O2 fat` | `0accc3bb...` | `0accc3bb...` |
| `red_tree` | `fat -DTREE_REDUCTION` | `a2c70538...` | `a2c70538...` |
| `red_atomic` | `fat -DATOMIC_REDUCTION` | `a2c70538...` | `a2c70538...` |

**Same kernel across two GPU architectures: identical output.**
**Different kernels on the same GPU: different output.**

Note: `fast_on` / `fast_off` compare the fast intrinsic `__expf` against
the accurate library function `expf`. These differ in both polynomial
approximation and FTZ behavior; the label reflects the fast-math path,
not an isolated FTZ toggle.

The divergence source on GPU is the execution path (FMA vs non-FMA,
fast intrinsic vs accurate library), not the hardware.

---

## Reproducing the CPU test

### 1. Verify the corpus

The corpus is committed to the repository as `test.bin`. Its SHA256 is:

    e851cab68f6e23507fc0a4f0ef2df82c86e288289a59e0f237570d3a9f469c19

Verify:

```bash
sha256sum test.bin
```

If the hash differs, do not proceed. The finding depends on every node
using a byte-identical input.

### 2. Copy test.bin to each node

Copy the file. Do not regenerate it.

### 3. Capture a run on each node

From the repository root, on every node, run:

```bash
./run_divergence_test.sh
```

or equivalently:

```bash
./capture_run.sh <node_label> test.bin --artifact float_output.bin -- ./divergence_demo.sh
```

This produces `manifest_<node_label>.json` in the repository root.

### 4. Compare

From the repository root:

```bash
python3 compare_runs.py
```

`compare_runs.py` scans the current directory for `manifest_*.json`.
It does not look in subdirectories. Run it from the repository root
after collecting all manifests there.

| Result | Meaning |
|--------|---------|
| `INVALID COMPARISON` | Binary or input hash differs -- test is void |
| `NO DIVERGENCE DETECTED` | Same binary, same input, same output |
| `UNEXPLAINED DIVERGENCE -- GENUINE FINDING` | Same binary, same input, different output |

---

## Reproducing the GPU test

### 1. Build fat binaries

The Makefile produces a fat binary containing SASS for sm_75
(Turing/T4) and sm_86 (Ampere/RTX 3050), plus PTX fallback. The
same binary file runs on both architectures.

```bash
cd cuda
make all
```

### 2. Transfer to each GPU machine

```bash
./build_fat_bundle.sh
# produces cuda_bundle_<timestamp>.tar.gz
```

Extract on the target machine and run:

```bash
./run_cuda_divergence_test.sh
```

The script detects pre-built binaries and skips compilation, then runs
all six kernels and writes manifests to `cuda/manifests/`.

### 3. Compare across machines

Copy all `manifest_gpu_*.json` files into `cuda/manifests/` and run:

```bash
cd cuda/manifests
python3 ../compare_cuda_runs.py
```

The script groups manifests by kernel, verifies binary hash identity
across machines, and reports whether output hashes diverge.

---

## Sample output (CPU)

```
$ python3 compare_runs.py

Loaded 6 node manifests:

  [0e4e583760c2]
    kernel      : Linux 6.6.122+ x86_64 GNU/Linux
    cpu_model   : Intel(R) Xeon(R) CPU @ 2.20GHz
    output_hash : 8f172ee242809dbf...

  [6e258a114c61]
    kernel      : Linux 6.6.122+ x86_64 GNU/Linux
    cpu_model   : Intel(R) Xeon(R) CPU @ 2.00GHz
    output_hash : 7989a6b20cc566cd...

  [Prime]
    kernel      : Linux 6.6.87.2-microsoft-standard-WSL2 x86_64 GNU/Linux
    cpu_model   : 12th Gen Intel(R) Core(TM) i5-12450HX
    output_hash : b266807160a9ee69...

  [c2e68d2ae4f6]
    kernel      : Linux 6.6.122+ x86_64 GNU/Linux
    cpu_model   : AMD EPYC 7B13
    output_hash : 44b36c0f3a01cc59...

  [project40c8f81744b8444da370e811d81e6c86]
    kernel      : Linux 6.17.0-1022-gcp x86_64 GNU/Linux
    cpu_model   : AMD EPYC 7B13
    output_hash : a1b49047410b2620...

  [second_pc]
    kernel      : Linux 4.4.0-26100-Microsoft x86_64 GNU/Linux
    cpu_model   : 12th Gen Intel(R) Core(TM) i7-1255U
    output_hash : 689c2e49eb09ec8b...

Binary identical: CONFIRMED
Input identical:  CONFIRMED

RESULT: UNEXPLAINED DIVERGENCE -- GENUINE FINDING
    8f172ee242809dbf...  <- ['0e4e583760c2']
    7989a6b20cc566cd...  <- ['6e258a114c61']
    b266807160a9ee69...  <- ['Prime']
    44b36c0f3a01cc59...  <- ['c2e68d2ae4f6']
    a1b49047410b2620...  <- ['project40c8f81744b8444da370e811d81e6c86']
    689c2e49eb09ec8b...  <- ['second_pc']
```

---

## Sample output (GPU)

```
$ python3 compare_cuda_runs.py

Loaded 12 GPU manifests:

  [Prime_gpu_fma_off]
    gpu          : NVIDIA GeForce RTX 3050 6GB Laptop GPU
    compute_cap  : 8.6
    kernel       : fma_off
    binary_sha   : 0cd5a05bc5de06e1...
    output_hash  : c0d12da384ac30a6...

  [d794f130e459_gpu_fma_off]
    gpu          : Tesla T4
    compute_cap  : 7.5
    kernel       : fma_off
    binary_sha   : 0cd5a05bc5de06e1...
    output_hash  : c0d12da384ac30a6...

  ... (12 manifests total)

Input identical: CONFIRMED

RESULT: CUDA DIVERGENCE -- GENUINE FINDING
Same input, different compile flags -> different output.
```

---

## Design constraints

`capture_run.sh` hashes the executable on disk, hashes the input file
before the run, clears any stale artifact before executing, and writes
a timestamped JSON manifest. It does not modify or canonicalize output.

`compare_runs.py` scans the current working directory for
`manifest_*.json`. Run it from the repository root after collecting
all CPU manifests there. It enforces that all nodes ran the same
capture mode before comparing. Mixed-mode comparisons (stdout on one
node, artifact on another) are rejected as invalid.

`test.bin` is the committed float32 corpus. It is the input for all
CPU runs. Its SHA256 is recorded above; every manifest carries the
same `input_sha256` value.

`divergence_demo.sh` reads `test.bin` and writes `float_output.bin`.
It does not regenerate the corpus.

`cuda/Makefile` builds fat binaries for cross-architecture testing.
The same binary file runs on both Turing and Ampere GPUs, so the
`binary_sha256` comparison is meaningful.

`cuda/compare_cuda_runs.py` groups manifests by kernel identity and
verifies binary hash identity before comparing outputs.

---

## Adding nodes

**CPU:** Copy `test.bin` to the new node. Run `run_divergence_test.sh`
from the repository root. The resulting `manifest_<node_label>.json`
lands in the repository root. Re-run `compare_runs.py` from the root.

**GPU:** Run `run_cuda_divergence_test.sh` on the new GPU machine.
Copy the resulting `cuda/manifests/manifest_gpu_*.json` into
`cuda/manifests/`. Re-run `compare_cuda_runs.py` from `cuda/manifests/`.

Hardware diversity is the point. Different CPU families (x86 vs ARM),
different kernels, different libc versions. The `cpu_flags_hash` field
in each manifest records the full CPU flags word for post-hoc analysis.

---

## License

MIT. The harness only. The test corpus (`test.bin`) is committed as
data and carries no separate rights.
