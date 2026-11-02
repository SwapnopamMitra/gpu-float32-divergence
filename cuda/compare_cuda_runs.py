import json, sys, glob
from collections import defaultdict

def load_manifests(pattern="manifests/manifest_*.json"):
    manifests = []
    for path in sorted(glob.glob(pattern)):
        with open(path) as f:
            manifests.append(json.load(f))
    return manifests

def main():
    manifests = load_manifests()
    if len(manifests) < 2:
        print(f"Found {len(manifests)} manifest(s). Need at least 2.")
        sys.exit(1)

    print(f"Loaded {len(manifests)} GPU manifests:\n")
    for m in manifests:
        print(f"  [{m['node_label']}]")
        print(f"    gpu          : {m.get('gpu_model','unknown')}")
        print(f"    cuda         : {m.get('cuda_version','unknown')}")
        # Note: we group by the basename of the command (e.g., 'fma_default')
        print(f"    kernel       : {m.get('kernel','unknown')}")
        print(f"    output_hash  : {m.get('raw_output_sha256','')[:16]}...")
        print()

    # 1. Validate input hash identity
    input_hashes = {m.get('input_sha256') for m in manifests}
    if len(input_hashes) > 1:
        print("RESULT: INVALID COMPARISON -- input file hash differs across nodes")
        sys.exit(2)
    print("Input identical: CONFIRMED\n")

    # 2. Group by kernel name
    groups = defaultdict(list)
    for m in manifests:
        # Fallback to nvcc_flags or command if kernel is missing
        key = m.get('kernel') or m.get('nvcc_flags') or m.get('command', 'unknown')
        groups[key].append(m)

    group_hashes = {}
    
    # 3. Compare outputs
    for key, ms in groups.items():
        out_hashes = {m.get('raw_output_sha256', '') for m in ms}
        
        # If the same kernel produced different outputs on different GPUs, warn.
        if len(out_hashes) > 1:
            print(f"WARNING: Same kernel '{key}' produced different output across machines.")
        
        group_hashes[key] = out_hashes.pop()

    if len(set(group_hashes.values())) == 1:
        print("RESULT: NO DIVERGENCE -- all kernels produced same output")
        sys.exit(0)
    else:
        print("RESULT: CUDA DIVERGENCE -- GENUINE FINDING")
        print("Same input, different compile flags -> different output.\n")
        for key, h in group_hashes.items():
            print(f"    {key:48s}  output={h[:16]}...")
        sys.exit(3)

if __name__ == "__main__":
    main()