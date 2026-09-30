#include "kseq/kseq.h"
#include "common.h"
#include <stdexcept>
#include <iostream>
#include <assert.h>
#include <stdexcept>

#define ALIGN_16(x) (((x) + 15) & ~15)

// changable through makefile
#ifndef BLOCK_SIZE
    #define BLOCK_SIZE 256
#endif
#ifndef NUM_STREAM
    #define NUM_STREAM 16
#endif
#ifndef SAMPLE_SUBSTRING_SIZE
    #define SAMPLE_SUBSTRING_SIZE 18320
#endif
#ifndef SIGNATURE_MAX_LENGTH
    #define SIGNATURE_MAX_LENGTH 10000
#endif
#ifndef GRID_MATCH
    #define GRID_MATCH 1
#endif

using std::vector;
using namespace klibpp;

struct cudaSample{
    int idx;
    char *seq;
    char *qual;
    int len;
};

struct StreamAssets {
    char *d_seqs; 
    char *d_quals;
    int  *d_confs;
};

void check_cuda_errors()
{
    cudaError_t rc;
    rc = cudaGetLastError();
    if (rc != cudaSuccess)
    {
        printf("Last CUDA error %s\n", cudaGetErrorString(rc));
    }

}

__device__ void warp_reduce(volatile int* sdata, int tid) {
    sdata[tid] = sdata[tid] + sdata[tid + 32];
    sdata[tid] = sdata[tid] + sdata[tid + 16];
    sdata[tid] = sdata[tid] + sdata[tid + 8];
    sdata[tid] = sdata[tid] + sdata[tid + 4];
    sdata[tid] = sdata[tid] + sdata[tid + 2];
    sdata[tid] = sdata[tid] + sdata[tid + 1];
}

__device__ void reduce(int* res, int* __restrict__ data){
    int tid = threadIdx.x;
    for(int s = blockDim.x/2; s > 32; s >>= 1) {
        if (tid < s) {
            data[tid] += data[tid + s];
        }
        __syncthreads();
    }
    if (tid < 32) warp_reduce(data, tid);
    if (tid == 0) *res = data[0];
}

__global__ void sum(int *integrity, const char* __restrict__ qual, int size){
    int idx = blockIdx.x * blockDim.x + threadIdx.x;

    extern __shared__ int data[];
    __shared__ int partialSum;

    if (threadIdx.x == 0) partialSum = 0;
    __syncthreads();

    if (idx < size) data[threadIdx.x] = qual[idx] - 33;
    else data[threadIdx.x] = 0;
    __syncthreads();

    reduce(&partialSum, data);
    if(threadIdx.x == 0) atomicAdd(integrity, partialSum);
}

__device__ void sharedMemCpy( char* __restrict__ dst, const char* __restrict__ src, int count, int srcLength, int srcOffset = 0){

    // assert(count & 15 == 0);
    if (srcOffset >= srcLength) return;
    int num = min(count, srcLength - srcOffset);
    int tid = threadIdx.x; 

    // vectorized version
    #ifdef VECTOR_MEM_LOAD
        int4 *d4 = (int4*)(dst);
        int4 *s4 = (int4*)(src+srcOffset);

        int round = (num + 15) >> 4;
        
        // load 4 char for each iteration
        for(int idx = tid; idx < round; idx+= blockDim.x){
            d4[idx] = s4[idx];
        }
    #else
        for(int idx = tid; idx < num; idx += blockDim.x){
            dst[idx] = src[srcOffset + idx];
        }
    #endif

}

void setIntegrity(int *hostIntegrity, const char* __restrict__ sample_qual, int sample_len, cudaStream_t stream){

    int num_block = (sample_len + BLOCK_SIZE - 1)/BLOCK_SIZE;
    // get score of each index first;

    int *deviceIntegrity;
    cudaMallocAsync((void **)&deviceIntegrity, sizeof(int), stream);
    cudaMemsetAsync(deviceIntegrity, 0, sizeof(int), stream);

    sum<<<num_block, BLOCK_SIZE, BLOCK_SIZE*sizeof(int), stream>>>(deviceIntegrity, sample_qual, sample_len);

    int tmp;
    cudaMemcpyAsync(&tmp, deviceIntegrity, sizeof(int), cudaMemcpyDeviceToHost, stream);
    
    cudaStreamSynchronize(stream);
    *hostIntegrity = tmp %97;
    cudaFreeAsync(deviceIntegrity, stream);
}

__global__ void kernelMatch(
    int* confidences,
    const char* __restrict__ sample_seq, 
    const char* __restrict__ sample_qual, 
    const int sample_len, 
    const char* __restrict__ signaturesFlatten, 
    const int* __restrict__ signature_lengths, 
    const int flattenLen,
    const int n_sig
    )
{
    
    //local index variables
    const int tid = threadIdx.x;
    
    // other variable
    int start_offset = blockIdx.x * (SAMPLE_SUBSTRING_SIZE - SIGNATURE_MAX_LENGTH);
    if (start_offset >= sample_len) return;

    int substring_len = min(ALIGN_16(sample_len) - start_offset, SAMPLE_SUBSTRING_SIZE);


    // dynamically allocated, shared memories 
    extern __shared__ char smem[];
    char *signature = smem;
    char *subSample = signature + ALIGN_16(SIGNATURE_MAX_LENGTH * sizeof(char));
    char *subQual = subSample + ALIGN_16(substring_len * sizeof(char));
    
    // if(!(substring_len & 15 == 0 && sample_len & 15 == 0 && start_offset & 15 == 0)){
    //     printf("%d\t%d\t%d\n", substring_len % 16, sample_len % 16, start_offset % 16);
    //     assert(substring_len&15 == 0 && sample_len&15 == 0 && start_offset&15 == 0);
    // }
    // load substring into each block
    sharedMemCpy(subSample, sample_seq, substring_len, sample_len, start_offset);
    sharedMemCpy(subQual, sample_qual, substring_len, sample_len, start_offset);

    // looping through virus
    // every block help check virus in one by one order
    int offset = 0;
    for(int k = blockIdx.y; k < n_sig; k += blockDim.y){
        
        // load signature into shared memory
        int len_sig = __ldg(&signature_lengths[k]);

        sharedMemCpy(signature, signaturesFlatten, ALIGN_16(len_sig), flattenLen, offset);
        offset += ALIGN_16(len_sig);
        __syncthreads();
        // const char* signature = signature_seqs[k];
        
        int threadBestScore = -1;
        const int window = substring_len - len_sig;
        for(int i = tid; i <= window; i += blockDim.x){
            
            int localScore = 0;
            #ifdef VECTOR_MATCH
            for(int j = 0; j < len_sig; j += 4){
                
                if (j + 4 > len_sig) {
                    for (; j < len_sig; j++) {
                        int cmp = subSample[i+j] ^ signature[j];
                        if (0xA80054 >> (cmp & 31) & 1) {
                            localScore = -1;
                            break;
                        } 
                        localScore += subQual[i + j] - 33; 
                    }
                    break;
                }

                uint32_t s_vec = ((uint32_t)(uint8_t)subSample[i+j]) | 
                                 (((uint32_t)(uint8_t)subSample[i+j+1]) << 8) | 
                                 (((uint32_t)(uint8_t)subSample[i+j+2]) << 16) | 
                                 (((uint32_t)(uint8_t)subSample[i+j+3]) << 24);
                                 
                uint32_t sig_vec = *(uint32_t*)(&signature[j]);

                uint32_t diff = s_vec ^ sig_vec;
                bool chunkFailed = false;
                                 
                #pragma unroll
                for(int byte = 0; byte < 4; byte++) {
                    uint8_t cmp = (diff >> (byte * 8)) & 0xFF;
                    chunkFailed |= (0xA80054 >> (cmp & 31) & 1);
                }
                
                if (chunkFailed) {
                    localScore = -1;
                    break;
                }
                
                uint32_t q_vec = ((uint32_t)(uint8_t)subQual[i+j]) | 
                    (((uint32_t)(uint8_t)subQual[i+j+1]) << 8) | 
                    (((uint32_t)(uint8_t)subQual[i+j+2]) << 16) | 
                    (((uint32_t)(uint8_t)subQual[i+j+3]) << 24);
                localScore += (int)__dp4a(q_vec, 0x01010101U, 0U) - 132;
            }
            #else
            for(int j = 0; j < len_sig; j++){
                int cmp = subSample[i+j] ^ signature[j];
                if (!(0x400A201 >> (cmp & 31) & 1)) {
                    localScore = -1;
                    break;
                }
                localScore += subQual[i + j] - 33; 
            }
            #endif
            threadBestScore = max(threadBestScore, localScore); 
        }
        if (threadBestScore >= 0) atomicMax(&confidences[k], threadBestScore);
        __syncthreads();
    }
}

void hostMatch(
    const cudaSample sample,
    const std::vector<klibpp::KSeq> &samples,
    const std::vector<klibpp::KSeq> &signatures,
    int* cudaConfidences,
    std::vector<MatchResult> &matches,
    cudaStream_t stream
    )
{   
    int n_sig = signatures.size();
    std::vector<int> hostConfidences(n_sig);
    cudaMemcpyAsync(hostConfidences.data(), cudaConfidences, n_sig * sizeof(int), cudaMemcpyDeviceToHost, stream);
    cudaStreamSynchronize(stream);

    int integrity = -1;
    for(int i = 0; i < signatures.size(); i++){
        int confidence = hostConfidences[i];

        if(confidence > -1) {
            // if integrate is never calculated before
            if(integrity == -1) setIntegrity(&integrity, sample.qual, sample.len, stream);
            
            double confidence_pct = (double)confidence / signatures[i].seq.length();
            MatchResult match = {samples[sample.idx].name, signatures[i].name, confidence_pct, integrity};
            matches.push_back(match);
        }
    }
}

int cudaVirusInit(char* &cudaVirusFlatten, int* &cudaVirusSizes, const std::vector<klibpp::KSeq> &signatures){

    int numVirus = signatures.size();
    std::vector<char> hostVirusFlatten(numVirus * SIGNATURE_MAX_LENGTH);
    std::vector<int> hostVirusSizes(numVirus);
    int totalLen = 0;

    // allocate memory to gpu
    cudaMalloc((void**)&cudaVirusFlatten, numVirus * SIGNATURE_MAX_LENGTH);
    for (int i = 0; i < numVirus; i++) {
        std::string sig = signatures[i].seq;
        hostVirusSizes[i] = sig.length();
        int padded = ALIGN_16(hostVirusSizes[i]);
        if(padded > hostVirusSizes[i]){
            sig += std::string(padded - hostVirusSizes[i], '*');
        }
        std::copy(sig.begin(), sig.end(), hostVirusFlatten.begin() + totalLen);
        totalLen += padded;
    }
    cudaMemcpy(cudaVirusFlatten, hostVirusFlatten.data(), totalLen, cudaMemcpyHostToDevice);
    cudaMalloc((void **)&cudaVirusSizes, numVirus*sizeof(int));
    cudaMemcpy(cudaVirusSizes, hostVirusSizes.data(), numVirus*sizeof(int), cudaMemcpyHostToDevice);
    return totalLen;

}

void cudaVirusEnd(char* &cudaVirusFlatten, int* &cudaVirusSizes){
    cudaFree(cudaVirusFlatten);
    cudaFree(cudaVirusSizes);
}

void cudaConfidenceInit(vector<int *> &cudaConfidences, int numVirus, std::vector<cudaStream_t> streams){
    for (int i = 0; i < cudaConfidences.size(); i++){
        cudaMallocAsync((void**)&cudaConfidences[i], numVirus * sizeof(int), streams[i % NUM_STREAM]);
        cudaMemsetAsync(cudaConfidences[i], -1, numVirus * sizeof(int), streams[i % NUM_STREAM]);
    }
}

void cudaConfidenceEnd(vector<int *> &cudaConfidences, std::vector<cudaStream_t> streams){
    for (int i = 0; i < cudaConfidences.size(); i++){
        cudaFreeAsync(cudaConfidences[i], streams[i % NUM_STREAM]);
    }
}

void cudaSampleInitAsync(char*& cudaSample, char*& cudaSampleQual, const klibpp::KSeq& sample, cudaStream_t stream){
    int sampleLen = sample.seq.length();
    
    int padded = ALIGN_16(sampleLen) - sampleLen;
    
    std::string seq = sample.seq;
    std::string qual = sample.qual;
    
    if(padded > 0){
        seq += std::string(padded, ' ');
        qual += std::string(padded, '!');
    }

    cudaMallocAsync((void **)&cudaSample, ALIGN_16(sampleLen), stream);
    cudaMallocAsync((void **)&cudaSampleQual, ALIGN_16(sampleLen), stream);
    
    cudaMemcpyAsync(cudaSample, seq.data(), ALIGN_16(sampleLen), cudaMemcpyHostToDevice, stream);
    cudaMemcpyAsync(cudaSampleQual, qual.data(), ALIGN_16(sampleLen), cudaMemcpyHostToDevice, stream);
}

void runMatcher(const std::vector<klibpp::KSeq>& samples, const std::vector<klibpp::KSeq>& signatures, std::vector<MatchResult>& matches) {


    #ifdef VECTOR_MEM_LOAD
    if (SAMPLE_SUBSTRING_SIZE & 15 && SIGNATURE_MAX_LENGTH & 15){
        throw std::runtime_error("Size of sample substring must be divisible by 16!");
    }
    #endif

    std::vector<cudaStream_t> streams(NUM_STREAM);
    for ( auto & s : streams ) cudaStreamCreate (&s);

    int n_sample = samples.size();
    int n_sig = signatures.size();


    // Initialize flattend series of viruses in contiguous order within GPU memory, which will be passed in kernel
    char* deviceViruses;
    int* deviceVirusSizes;
    int flattenLen = cudaVirusInit(deviceViruses, deviceVirusSizes, signatures);

    // initialize confidences in GPU memory address, same as virus
    vector<int *> DeviceAllConfidences(n_sample);
    cudaConfidenceInit(DeviceAllConfidences, n_sample, streams);

    
    // check sample one-by-one
    std::vector<char*> d_seqs(n_sample), d_quals(n_sample);
    for(int i = 0; i < n_sample; i++){
        // identify stream
        int streamIdx = i % NUM_STREAM;
        int sampleLen = samples[i].seq.size();
        cudaStream_t stream = streams[streamIdx];

        // prepare sample strings for kernel
        cudaSampleInitAsync(d_seqs[i], d_quals[i], samples[i], stream);

        // perform matching
        // calculate number of block needed to be called on kernel and size of dynamic shared memory
        int chunk_stride = SAMPLE_SUBSTRING_SIZE - SIGNATURE_MAX_LENGTH;
        int num_block = (sampleLen + chunk_stride - 1) / chunk_stride;
        int substring_len = min(sampleLen, SAMPLE_SUBSTRING_SIZE);
        int shared_dynamic = ALIGN_16(SIGNATURE_MAX_LENGTH) + 2 * ALIGN_16(substring_len);

        // call matchKernel to to evaluate confidence of each sample and signature pair
        // if there is a match, then confidence is the total score of best match, otherwise -1
        dim3 grid(num_block, GRID_MATCH);
        #ifdef VECTOR_MEM_LOAD
        kernelMatch<<<grid,BLOCK_SIZE,shared_dynamic,stream>>>(DeviceAllConfidences[i], d_seqs[i], d_quals[i], ALIGN_16(sampleLen), deviceViruses, deviceVirusSizes, flattenLen, n_sig);
        #else
        kernelMatch<<<grid,BLOCK_SIZE,shared_dynamic,stream>>>(DeviceAllConfidences[i], d_seqs[i], d_quals[i], sampleLen, deviceViruses, deviceVirusSizes, flattenLen, n_sig);
        #endif
       
    }

    for(int i = 0; i < n_sample; i++){
        cudaStream_t stream = streams[i % NUM_STREAM];
        int len_sample = samples[i].seq.size();
        
        cudaSample d_sample{i, d_seqs[i], d_quals[i], len_sample};

        hostMatch(d_sample, samples, signatures, DeviceAllConfidences[i], matches, stream);
        
        // free sample sequence and quality string
        cudaFreeAsync(d_seqs[i], stream);
        cudaFreeAsync(d_quals[i], stream);
    }
    cudaDeviceSynchronize();

    // Finally free GPU memory
    cudaVirusEnd(deviceViruses, deviceVirusSizes);
    cudaConfidenceEnd(DeviceAllConfidences, streams);

    check_cuda_errors();
}


