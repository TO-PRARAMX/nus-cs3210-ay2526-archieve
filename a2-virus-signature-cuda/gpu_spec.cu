#include <iostream>

int main() {
  int nDevices;

  cudaGetDeviceCount(&nDevices);
  for (int i = 0; i < nDevices; i++) {
    cudaDeviceProp prop;
    cudaGetDeviceProperties(&prop, i);
    printf("Device Number: %d\n", i);
    printf("=== OVERALL ===\n");
    printf("  Device name: %s\n", prop.name);
    printf("  Memory Clock Rate (KHz): %d\n",
           prop.memoryClockRate);
    printf("  Memory Bus Width (bits): %d\n",
           prop.memoryBusWidth);
    printf("  Peak Memory Bandwidth (GB/s): %f\n",
           2.0*prop.memoryClockRate*(prop.memoryBusWidth/8)/1.0e6);
    printf("=== MULTIPROCESSOR ===\n");
    printf("  Number of Multiprocessor: %d\n", prop.multiProcessorCount);
    printf("  Maximum Registers per SM: %d\n", prop.regsPerMultiprocessor);
    printf("=== MEMORY ===\n");
    printf("  Total Global Memory (GB): %.2f\n", prop.totalGlobalMem/1e9);
    printf("  Memory per SM (Bytes): %zu\n", prop.sharedMemPerMultiprocessor);
    printf("  Maximum Blocks per SM: %d\n", prop.maxBlocksPerMultiProcessor);
    printf("  Maximum Memory per Block (Bytes): %zu\n", prop.sharedMemPerBlock);
    printf("  Maximum Threads Per Block: %d\n", prop.maxThreadsPerBlock);
    printf("  Register Per Block: %d\n", prop.regsPerBlock);
    printf("\n");
  }
}