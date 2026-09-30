cmake_minimum_required(VERSION 3.18) # 3.18+ recommended for modern CUDA support

project(CudaMatcher 
        VERSION 1.0 
        LANGUAGES CXX CUDA)

# --- 1. Interactive Parameters (User-Configurable) ---
# Usage: cmake -DBLOCK_SIZE=512 ..
set(BLOCK_SIZE 256 CACHE STRING "CUDA Block Size")
set(NUM_STRERAM 16 CACHE STRING "Number of CUDA streams")
set(SAMPLE_SUBSTRING_SIZE 16384 CACHE STRING "Sample substring size")
set(SIGNATURE_MAX_LENGTH 10000 CACHE STRING "Signature max length")
set(GRID_MATCH 1 CACHE STRING "Grid match flag")

# 2. Add validation logic immediately after
foreach(VAR BLOCK_SIZE NUM_STRERAM SAMPLE_SUBSTRING_SIZE SIGNATURE_MAX_LENGTH)
    if(NOT ${${VAR}} MATCHES "^[0-9]+$")
        message(FATAL_ERROR "Variable ${VAR} is set to '${${VAR}}', but it must be an integer.")
    endif()
endforeach()
math(EXPR sample_mod_16 "${SAMPLE_SUBSTRING_SIZE} % 16")
if(sample_mod_16 EQUAL 0)
    message("${SAMPLE_SUBSTRING_SIZE} MUST be divisible by 16")
endif()

# --- 2. Interactive Optimizer Switch ---
# Usage: cmake -DVECTOR_MEM_LOAD=ON ..
option(VECTOR_MEM_LOAD "Enable vector memory loading optimization" ON)
option(WARP_TILE "Enable string matching by warp" ON)

# --- 3. Compiler Settings ---
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# NVCC specific flags (replacing your -lineinfo -dlto -arch=native)
set(CMAKE_CUDA_ARCHITECTURES native)
add_compile_options("$<$<COMPILE_LANGUAGE:CUDA>:-lineinfo;-O3>")

# Global definitions for the GPU target
add_definitions(
    -DBLOCK_SIZE=${BLOCK_SIZE}
    -DNUM_STRERAM=${NUM_STRERAM}
    -DSAMPLE_SUBSTRING_SIZE=${SAMPLE_SUBSTRING_SIZE}
    -DSIGNATURE_MAX_LENGTH=${SIGNATURE_MAX_LENGTH}
    -DGRID_MATCH=${GRID_MATCH}
)

if(VECTOR_MEM_LOAD)
    add_definitions(-DVECTOR_MEM_LOAD)
endif()

if(WARP_TILE)
    add_definitions(-DWARP_TILE)
endif()

# --- 4. Define Targets ---

# Target: gen_sample
add_executable(gen_sample gen_sample.cc)

# Target: gen_sig
add_executable(gen_sig gen_sig.cc)

# Target: matcher (The GPU target)
add_executable(matcher kernel_skeleton.cu common.cc)

# --- 5. Include Paths ---
# Ensures kseq/kseq.h is found if it's in the project root
target_include_directories(matcher PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})