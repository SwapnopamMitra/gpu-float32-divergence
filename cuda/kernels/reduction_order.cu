#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cstdlib>

__global__ void kernel_reduce(const float *in, float *out, int n) {
    extern __shared__ float sdata[];
    int tid = threadIdx.x;
    int i   = blockIdx.x * blockDim.x + threadIdx.x;

    sdata[tid] = (i < n) ? in[i] : 0.0f;
    __syncthreads();

#ifdef TREE_REDUCTION
    for (int s = blockDim.x / 2; s > 0; s >>= 1) {
        if (tid < s) sdata[tid] += sdata[tid + s];
        __syncthreads();
    }
    // Write block result to global memory at the block index
    if (tid == 0) out[blockIdx.x] = sdata[0];
    
#elif defined(ATOMIC_REDUCTION)
    volatile float* v_out = out;
    
    if (i < n) {
        if ((tid + blockIdx.x) % 32 == 0) {
            __nanosleep(10); 
        }
        atomicAdd((float*)v_out, in[i]);
    }
#endif
}

int main(int argc, char **argv) {
    const char *inpath  = (argc > 1) ? argv[1] : "test.bin";
    const char *outpath = (argc > 2) ? argv[2] : "output/reduction_output.bin";

    FILE *f = fopen(inpath, "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", inpath); return 1; }
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    rewind(f);
    int n = (int)(len / 4);
    uint32_t *host_in = (uint32_t*)malloc(len);
    if (fread(host_in, 1, len, f) != (size_t)len) { fclose(f); return 1; }
    fclose(f);

    int threads = 256;
    int blocks  = (n + threads - 1) / threads;
    size_t shmem = threads * sizeof(float);

    float *d_in, *d_out;
    cudaMalloc(&d_in,  n * sizeof(float));
    
    // Allocate memory for the block results on GPU
    cudaMalloc(&d_out, blocks * sizeof(float));
    cudaMemcpy(d_in, host_in, n * sizeof(float), cudaMemcpyHostToDevice);

    // Initialize output buffer to 0
    cudaMemset(d_out, 0, blocks * sizeof(float));

    kernel_reduce<<<blocks, threads, shmem>>>(d_in, d_out, n);
    cudaDeviceSynchronize();

    float h_sum = 0.0f;
    
#ifdef TREE_REDUCTION
    // Copy all block results back to CPU
    float *h_blocks = (float*)malloc(blocks * sizeof(float));
    cudaMemcpy(h_blocks, d_out, blocks * sizeof(float), cudaMemcpyDeviceToHost);
    
    // Sum them sequentially on the host to guarantee determinism
    for (int i = 0; i < blocks; i++) {
        h_sum += h_blocks[i];
    }
    free(h_blocks);
#else
    // For atomic, the final answer is already in d_out[0]
    cudaMemcpy(&h_sum, d_out, sizeof(float), cudaMemcpyDeviceToHost);
#endif

    FILE *o = fopen(outpath, "wb");
    fwrite(&h_sum, sizeof(float), 1, o);
    fclose(o);

    printf("SUM_BITS: 0x%08x\n", *(uint32_t*)&h_sum);
    printf("WROTE: %s\n", outpath);

    cudaFree(d_in); cudaFree(d_out);
    free(host_in);
    return 0;
}
