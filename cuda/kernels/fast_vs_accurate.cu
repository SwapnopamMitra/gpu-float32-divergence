
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <cmath>

__global__ void kernel_ftz(const float *in, float *out, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    float x = in[i];
#ifdef USE_FAST
    out[i] = __expf(x);
#else
    out[i] = expf(x);
#endif
}

int main(int argc, char **argv) {
    const char *inpath  = (argc > 1) ? argv[1] : "test.bin";
    const char *outpath = (argc > 2) ? argv[2] : "output/ftz_output.bin";

    FILE *f = fopen(inpath, "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", inpath); return 1; }
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    rewind(f);
    int n = (int)(len / 4);
    uint32_t *host_in = (uint32_t*)malloc(len);
    if (fread(host_in, 1, len, f) != (size_t)len) { fclose(f); return 1; }
    fclose(f);

    float *d_in, *d_out;
    cudaMalloc(&d_in,  n * sizeof(float));
    cudaMalloc(&d_out, n * sizeof(float));
    cudaMemcpy(d_in, host_in, n * sizeof(float), cudaMemcpyHostToDevice);

    int threads = 256;
    int blocks  = (n + threads - 1) / threads;

    kernel_ftz<<<blocks, threads>>>(d_in, d_out, n);
    cudaDeviceSynchronize();

    uint32_t *host_out = (uint32_t*)malloc(n * 4);
    cudaMemcpy(host_out, d_out, n * 4, cudaMemcpyDeviceToHost);

    FILE *o = fopen(outpath, "wb");
    fwrite(host_out, 1, n * 4, o);
    fclose(o);

#ifdef USE_FAST
    printf("MODE: FTZ_ON\n");
#else
    printf("MODE: FTZ_OFF\n");
#endif
    printf("WROTE: %s\n", outpath);

    cudaFree(d_in); cudaFree(d_out);
    free(host_in); free(host_out);
    return 0;
}
