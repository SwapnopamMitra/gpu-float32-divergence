#!/bin/bash
# divergence_demo.sh

echo "=== Divergence Capture ==="
echo "Node: $(hostname)"
echo "CPU: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')"
echo ""

# Check for test.bin
if [ ! -f test.bin ]; then
    echo "ERROR: test.bin not found."
    exit 1
fi

# C code
cat > /tmp/float_test.c << 'EOF'
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <fenv.h>

int main() {
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
    
    for (int i = 0; i < count; i++) memcpy(&floats[i], &words[i], 4);
    
    for (int i = 0; i < count; i++) {
        float a = floats[i];
        float b = expf(a);
        float c = logf(fabsf(a) + 1.0f);
        float d = sinf(a);
        float e = cosf(a);
        
        if (i % 2 == 0) output[i] = b * c + d - e;
        else            output[i] = b / (c + 0.0001f) + e * d;
    }
    
    uint32_t *out = malloc(count * 4);
    for (int i = 0; i < count; i++) memcpy(&out[i], &output[i], 4);
    
    f = fopen("float_output.bin", "wb");
    fwrite(out, 1, count * 4, f);
    fclose(f);
    return 0;
}
EOF

# Compile and run
gcc -O0 -o /tmp/float_test /tmp/float_test.c -lm
/tmp/float_test

# Hash the output
if [ -f float_output.bin ]; then
    FULL_HASH=$(sha256sum float_output.bin | cut -d' ' -f1)
    echo "$FULL_HASH" > hash_output.txt
    echo "FULL_SHA256: $FULL_HASH"
else
    echo "ERROR: float_output.bin not generated"
    exit 1
fi