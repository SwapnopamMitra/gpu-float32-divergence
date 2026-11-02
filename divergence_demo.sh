#!/bin/bash
# divergence_demo_guaranteed.sh - Guaranteed divergence

echo "=== Divergence Capture (Guaranteed) ==="
echo "Node: $(hostname)"
echo "CPU: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')"
echo ""

# Generate test data
python3 -c "
import struct, random, hashlib, math

random.seed(42)
vals = []

# Create values that trigger different glibc behaviors
for i in range(1000):
    # Random floats with different exponents
    vals.append(random.randint(0x00000000, 0xFFFFFFFF))

# Include known problematic values
vals += [0x3F800000, 0xBF800000]  # 1.0, -1.0
vals += [0x00000001, 0x80000001]  # Subnormals
vals += [0x7F800000, 0xFF800000]  # Infinities
vals += [0x7FC00000, 0xFFC00000]  # Quiet NaNs

data = b''.join(struct.pack('<I', v) for v in vals)
open('test.bin', 'wb').write(data)
"

# CRITICAL: Use C code that calls glibc math functions
# Different glibc versions implement these DIFFERENTLY
cat > /tmp/float_test.c << 'EOF'
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <fenv.h>

int main() {
    // Turn off all rounding modes - use hardware defaults
    fesetround(FE_TONEAREST);
    
    FILE *f = fopen("test.bin", "rb");
    if (!f) return 1;
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    rewind(f);
    uint32_t *words = malloc(len);
    fread(words, 1, len, f);
    fclose(f);
    
    int count = len / 4;
    float *floats = malloc(count * sizeof(float));
    float *output = malloc(count * sizeof(float));
    
    for (int i = 0; i < count; i++) {
        memcpy(&floats[i], &words[i], 4);
    }
    
    // Operations that use glibc math functions
    // glibc 2.35 vs 2.39 have different implementations
    for (int i = 0; i < count; i++) {
        float a = floats[i];
        
        // These functions have different implementations across glibc versions
        float b = expf(a);      // expf - different in glibc 2.35 vs 2.39
        float c = logf(fabsf(a) + 1.0f);  // logf - different implementations
        float d = sinf(a);      // sinf - different in glibc versions
        float e = cosf(a);      // cosf - different in glibc versions
        
        // Combine them
        if (i % 2 == 0) {
            output[i] = b * c + d - e;
        } else {
            output[i] = b / (c + 0.0001f) + e * d;
        }
    }
    
    // Convert back
    uint32_t *out = malloc(count * 4);
    for (int i = 0; i < count; i++) {
        memcpy(&out[i], &output[i], 4);
    }
    
    f = fopen("float_output.bin", "wb");
    fwrite(out, 1, count * 4, f);
    fclose(f);
    
    return 0;
}
EOF

gcc -O0 -o /tmp/float_test /tmp/float_test.c -lm
/tmp/float_test

if [ -f float_output.bin ]; then
    FULL_HASH=$(sha256sum float_output.bin | cut -d' ' -f1)
    echo "FULL_SHA256: $FULL_HASH"
    echo "$FULL_HASH" > hash_output.txt
else
    echo "ERROR: No output generated"
    exit 1
fi
