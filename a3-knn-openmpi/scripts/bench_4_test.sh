#!/bin/bash
#SBATCH --job-name=knn_b4
#SBATCH --output=logs/engine_out_%j.log
#SBATCH --error=logs/engine_err_%j.err
#SBATCH --nodelist=soctf-pdc-033,soctf-pdc-030
#SBATCH --nodes=2                          # Exactly 2 nodes
#SBATCH --ntasks=40                        # 24 total ranks
#SBATCH --time=00:10:00                    # Set a reasonable limit
#SBATCH --mem=0                            # Request all available memory on nodes (optional)

make clean
make


echo "Running on nodes: $SLURM_JOB_NODELIST"
# Execute the engine
# Note: --input=0 is specific to your cluster's srun wrapper for stdin
echo "Running mine"
srun --input=0 ./engine < inputs/input3.in > OUT_MINE

echo "Running ref"
srun --input=0 ./benchmarks/bench_4 < inputs/input3.in > OUT_REF
