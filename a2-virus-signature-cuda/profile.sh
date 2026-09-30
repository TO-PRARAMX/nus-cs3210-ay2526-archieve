#!/bin/bash
#SBATCH --time=00:10:00
#SBATCH --job-name=matcher_profile
#SBATCH --output=output/%j.log
#SBATCH --error=output/%j.log
#SBATCH --ntasks=1
#SBATCH --mem=20G
#SBATCH --gpus=h100-47

MODE=$1             # normal, nsys, or ncu
EXE=$2              # your executable
SAMP=$3             # sample folder name
SIG=$4              # signature name

# Common srun prefix to save space
SRUN="srun --cpus-per-task=1 --cpu_bind core"
ARGS="$SAMP $SIG"
REPORT=Nsight/report_$SLURM_JOB_ID

echo "job id: ${SLURM_JOB_ID}"
echo "GPU: ${SLURM_JOB_GPUS}"

mkdir -p Nsight

if [ "$MODE" == "nsys" ]; then
    $SRUN nsys profile --cuda-event-trace=false -f true -o $REPORT $EXE $ARGS

elif [ "$MODE" == "ncu" ]; then
    $SRUN ncu --set full -s 20 -c 20 --clock-control none -f --import-source yes -o $REPORT $EXE $ARGS

else
    $SRUN $EXE $ARGS
fi

# Example
# sbatch ./profile.sh normal ./matcher samp.fastq sig.fasta
# sbatch --gpus=a100-80 ./profile.sh nsys ./matcher samp.fastq sig.fasta h100-47

