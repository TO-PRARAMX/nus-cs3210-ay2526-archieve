#!/bin/bash
#SBATCH --job-name=myjob
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --mem=1gb
#SBATCH --time=00:15:00
#SBATCH --output=log/%j.log
#SBATCH --error=log/%j.log
##SBATCH --partition=i7-13700

mkdir -p log
mkdir -p perf_report

echo " Running job !"
echo "We are running on $( hostname )"
echo "Job started at $( date )"
# NOTE : LINE BELOW CHANGED TO RUN COND

divider=$(printf '=%.0s' {1..50})
echo "$divider"
echo "BENCHMARK 4 PERFORMANCE STATISTICS"
echo "input file: inputs/in_5e6"
echo "partition: ${SLURM_JOB_PARTITION}"
echo "$divider"

srun perf stat -r 10 -e user_time,cycles,instructions,LLC-loads,LLC-load-misses -- bash -c "executables/bench-4.perf < inputs/in_5e6 > /dev/null"
srun perf record -e instructions,cycles,LLC-load-misses -o "perf_report/${SLURM_JOB_ID}_report.data" -- executables/bench-4.perf < inputs/in_5e6 > /dev/null
echo "Job ended at $( date )"