#!/bin/bash
#SBATCH --job-name=matcher
#SBATCH --output=output/%j.log
#SBATCH --error=output/%j.log
#SBATCH --ntasks=1
#SBATCH --gpus=h100-47
#SBATCH --time=10:00:00

mkdir -p output

make clean
make -j8
./matcher samp.fastq sig.fasta
