#!bin/bash

$SAMP=$1
$SIG=$2
$EXE=$3

$INPUTS = "$SAMP $SIG"
$SRUN = srun --ntasks 1 --cpus-per-task 1 --cpu_bind core --mem 20G --gpus h100-47
$SRUN bash -c "make clean && make -j8 && diff <($EXE $INPUTS) <(./bench-h100-1 $INPUTS)"
make clean