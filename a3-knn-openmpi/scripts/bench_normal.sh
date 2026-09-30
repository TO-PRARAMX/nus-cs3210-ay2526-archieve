#!/bin/bash
#SBATCH --job-name=knn_b4
#SBATCH --output=logs/%j.log
#SBATCH --error=logs/%j.err
#SBATCH --nodelist=soctf-pdc-033,soctf-pdc-030
#SBATCH --nodes=2
#SBATCH --ntasks=40
#SBATCH --time=00:10:00
#SBATCH --mem=0

make clean
make

# Adjust these values as needed for your specific test
D=100000
Q=10000
A=100
K=1000
LABELS=100
INPUT_FILE="inputs/random_input.bin"

mkdir -p inputs logs

# --- 3. Generate Random Input ---
echo "Generating random input: D=$D, Q=$Q, A=$A, K=$K..."
# We use your existing python generator for format consistency
python3 generate_input.py \
    --num_data $D \
    --num_queries $Q \
    --num_attrs $A \
    --min 1 --max 100000 \
    --minK $K --maxK $K \
    --num_labels $LABELS \
    --output $INPUT_FILE \
    --seed $RANDOM

# --- 4. Execution ---
echo "Running on nodes: $SLURM_JOB_NODELIST"

echo "Running [MINE]"
srun --input=0 ./engine < $INPUT_FILE > OUT_MINE

echo "Running [REF]"
srun --input=0 ./benchmarks/bench_4 < $INPUT_FILE > OUT_REF
