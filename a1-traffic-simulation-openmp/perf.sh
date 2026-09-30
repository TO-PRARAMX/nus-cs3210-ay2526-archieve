#!/bin/bash
#SBATCH --job-name=myjob
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --mem=1gb
#SBATCH --time=00:20:00
#SBATCH --output=log/%j.log
#SBATCH --error=log/%j.log
##SBATCH --partition=i7-7700

INPUT=$1
NUM_THREADS=${2:-${SLURM_CPUS_PER_TASK:-16}}
export OMP_NUM_THREADS=$NUM_THREADS

mkdir -p log
mkdir -p perf_report

echo " Running job !"
echo "We are running on $( hostname )"
echo "Job started at $( date )"


divider=$(printf '=%.0s' {1..50})
echo "$divider"
echo "USER EXECUTABLE PERFORMANCE STATISTICS"
echo "input file: $INPUT"
echo "partition: ${SLURM_JOB_PARTITION}"
if [ -n "${SLURM_CPUS_PER_TASK}" ]; then
echo "number of threads: $NUM_THREADS$"
fi
echo "$divider"

# 5 iteration of threads
srun perf stat -r 10 -e user_time,cycles,instructions,LLC-loads,LLC-load-misses -- bash -c "./sim.perf < $INPUT > /dev/null"
#srun perf record -B -N -e instructions,cycles,LLC-load-misses -o "perf_report/${SLURM_JOB_ID}_report.data" -- ./sim.perf < $INPUT > /dev/null
echo "Job ended at $( date )"
