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
    if (tid == 0) atomicAdd(out, sdata[0]);
    
#elif defined(ATOMIC_REDUCTION)
    // Cast to volatile to force the compiler to actually emit the atomic instruction
    // and not optimize the floating-point race condition away.
    volatile float* v_out = out;
    
    if (i < n) {
        // Introduce microscopic scheduling jitter based on thread/warp ID.
        // This forces different blocks to arrive at the memory controller out of order.
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

    float *d_in, *d_sum;
    cudaMalloc(&d_in,  n * sizeof(float));
    cudaMalloc(&d_sum, sizeof(float));
    cudaMemcpy(d_in, host_in, n * sizeof(float), cudaMemcpyHostToDevice);

    int threads = 256;
    int blocks  = (n + threads - 1) / threads;
    size_t shmem = threads * sizeof(float);

    float h_sum = 0.0f;
    cudaMemcpy(d_sum, &h_sum, sizeof(float), cudaMemcpyHostToDevice);

    kernel_reduce<<<blocks, threads, shmem>>>(d_in, d_sum, n);
    cudaDeviceSynchronize();

    cudaMemcpy(&h_sum, d_sum, sizeof(float), cudaMemcpyDeviceToHost);

    FILE *o = fopen(outpath, "wb");
    fwrite(&h_sum, sizeof(float), 1, o);
    fclose(o);

    printf("SUM_BITS: 0x%08x\n", *(uint32_t*)&h_sum);
    printf("WROTE: %s\n", outpath);

    cudaFree(d_in); cudaFree(d_sum);
    free(host_in);
    return 0;
}
