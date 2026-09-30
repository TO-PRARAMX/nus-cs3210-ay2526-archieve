# Makefile

NVCC        := /usr/local/cuda/bin/nvcc
COMMON_SRCS := common.cc
HEADERS := kseq/kseq.h

CXXFLAGS := -std=c++20 -O3

# optimizer
OPTIMIZE := 
VECTOR_MEM_LOAD ?= 1
VECTOR_MATCH ?= 1
ifeq ($(VECTOR_MEM_LOAD), 1)
    OPTIMIZE += -DVECTOR_MEM_LOAD
endif
ifeq ($(VECTOR_MATCH), 1)
    OPTIMIZE += -DVECTOR_MATCH
endif

# parameters
BLOCK_SIZE ?= 512
NUM_STREAM ?= 16
SAMPLE_SUBSTRING_SIZE ?= 18320
SIGNATURE_MAX_LENGTH ?= 10000
GRID_MATCH ?= 1

PARAM := -DBLOCK_SIZE=$(BLOCK_SIZE) \
		-DNUM_STREAM=$(NUM_STREAM) \
		-DSAMPLE_SUBSTRING_SIZE=$(SAMPLE_SUBSTRING_SIZE) \
		-DSIGNATURE_MAX_LENGTH=$(SIGNATURE_MAX_LENGTH) \
		-DGRID_MATCH=$(GRID_MATCH)
	 
OUTPUT_GEN  := gen_sample
OUTPUT_GEN_SIG  := gen_sig
OUTPUT_GPU  := matcher

.DEFAULT_TARGET: all

all: $(OUTPUT_GEN) $(OUTPUT_GEN_SIG) $(OUTPUT_GPU)

$(OUTPUT_GPU): kernel_skeleton.cu $(COMMON_SRCS)
	$(NVCC) $(CXXFLAGS) $(PARAM) $(OPTIMIZE) -lineinfo -dlto -arch=native -o $@ $^

$(OUTPUT_GEN): gen_sample.cc 
	$(CXX) $(CXXFLAGS) -o $@ $^

$(OUTPUT_GEN_SIG): gen_sig.cc 
	$(CXX) $(CXXFLAGS) -o $@ $^

clean:
	rm -f $(OUTPUT_GEN) $(OUTPUT_GEN_SIG) $(OUTPUT_GPU)
