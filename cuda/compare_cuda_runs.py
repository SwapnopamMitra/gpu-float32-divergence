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
        print(f"    nvcc_flags   : {m.get('nvcc_flags','unknown')}")
        print(f"    binary_sha   : {m.get('binary_sha256','')[:16]}...")
        print(f"    input_hash   : {m.get('input_sha256','')[:16]}...")
        print(f"    output_hash  : {m.get('raw_output_sha256','')[:16]}...")
        print()

    input_hashes = {m.get('input_sha256') for m in manifests}
    if len(input_hashes) > 1:
        print("RESULT: INVALID COMPARISON -- input file hash differs across nodes")
        sys.exit(2)

    groups = defaultdict(list)
    for m in manifests:
        key = m.get('kernel', m.get('nvcc_flags', 'unknown'))
        groups[key].append(m)

    print("Input identical: CONFIRMED\n")

    group_hashes = {}
    valid_comparison = True

    for key, ms in groups.items():
        bin_hashes = {m.get('binary_sha256', '') for m in ms}
        if len(bin_hashes) > 1:
            print(f"RESULT: INVALID COMPARISON -- binary hash differs across nodes for kernel '{key}'")
            print(f"  Found hashes: {[h[:16]+'...' for h in bin_hashes]}")
            valid_comparison = False
            continue

        out_hashes = {m.get('raw_output_sha256', '') for m in ms}
        if len(out_hashes) > 1:
            print(f"WARNING: Same binary and input, but different output within kernel '{key}' across GPUs.")
        group_hashes[key] = out_hashes.pop()

    if not valid_comparison:
        sys.exit(2)

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
