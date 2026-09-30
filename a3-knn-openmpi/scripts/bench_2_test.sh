#!/bin/bash
#SBATCH --job-name=knn_b2
#SBATCH --output=logs/engine_out_%j.log
#SBATCH --error=logs/engine_err_%j.err
#SBATCH --nodelist=soctf-pdc-015,soctf-pdc-030
#SBATCH --nodes=2                          # Exactly 2 nodes
#SBATCH --ntasks=32                        # 24 total ranks
#SBATCH --time=00:10:00                    # Set a reasonable limit

make clean
make

echo "Running on nodes: $SLURM_JOB_NODELIST"

# Execute the engine
# Note: --input=0 is specific to your cluster's srun wrapper for stdin
echo "Running mine"
srun --input=0 ./engine < inputs/input2.in > OUT_MINE

echo "Running ref"
srun --input=0 ./benchmarks/bench_2 < inputs/input2.in > OUT_REF
