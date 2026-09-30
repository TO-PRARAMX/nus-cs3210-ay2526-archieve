#!/bin/bash
#SBATCH --job-name=knn_b4
#SBATCH --output=logs/logs/num_data/%j
#SBATCH --error=logs/errs/num_data/%j
#SBATCH --nodes=2
#SBATCH --exclusive
#SBATCH --time=0:45:00
#SBATCH --mem=0

# ntask and nodelist will be passed as a CLI argument

INPUT_FILE="inputs/in_bench_num_tasks.in"



ATTR=100
# DATA=100000
MIN=-1000000
MAX=1000000
MINK=100
MAXK=1000
QUERY=10000
NUM_CLASS=100

mkdir -p inputs

for DATA in 1000 5000 10000 50000 100000
do 
echo "---------------------------------------" >&2 
echo "Job ID: $SLURM_JOB_ID" >&2
echo "Nodes assigned: $SLURM_NODELIST">&2
echo "Number of tasks: $SLURM_NTASKS" >&2
echo "Number of datapoints: $DATA" >&2 
INPUT_FILE="inputs/dataset-$DATA.in"
python3 generate_input.py --num_data $DATA --num_queries $QUERY --num_attrs $ATTR --min $MIN --max $MAX --minK $MINK --maxK $MAXK --num_labels $NUM_CLASS --output $INPUT_FILE
srun --input=0 ./engine < $INPUT_FILE > /dev/null
srun --input=0 ./engine < $INPUT_FILE > /dev/null
srun --input=0 ./engine < $INPUT_FILE > /dev/null
srun --input=0 ./engine < $INPUT_FILE > /dev/null
srun --input=0 ./engine < $INPUT_FILE > /dev/null
echo "---------------------------------------" >&2
done