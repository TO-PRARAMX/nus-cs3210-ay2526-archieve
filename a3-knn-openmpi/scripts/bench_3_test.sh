#!/bin/bash
#SBATCH --job-name=knn_b3
#SBATCH --output=logs/%j.log
#SBATCH --error=logs/%j.err
#SBATCH --nodelist=soctf-pdc-034,soctf-pdc-035
#SBATCH --nodes=2                          # Exactly 2 nodes
#SBATCH --ntasks=32                        # 24 total ranks
#SBATCH --time=00:10:00                    # Set a reasonable limit
#SBATCH --mem=0                            # Request all available memory on nodes (optional)

make clean
make

echo "Running on nodes: $SLURM_JOB_NODELIST"

# Execute the engine
# Note: --input=0 is specific to your cluster's srun wrapper for stdin
echo "Running mine"
srun --input=0 perf stat -e L1-dcache-loads,L1-dcache-load-misses,LLC-loads,LLC-load-misses ./engine < inputs/input2.in > OUT_MINE

echo "Running ref"
srun --input=0 ./benchmarks/bench_3 < inputs/input2.in > OUT_REF
