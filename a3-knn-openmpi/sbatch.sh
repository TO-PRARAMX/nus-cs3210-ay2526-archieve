#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <bench_script.sh>"
    exit 1
fi

SCRIPT=$1

if [ ! -f "$SCRIPT" ]; then
    echo "Error: script '$SCRIPT' not found"
    exit 1
fi

mkdir -p logs

# Node configurations: "constraint ntasks label"
CONFIGS=(
    "[i7-7700*1&i7-13700*1] 24"
    "[i7-7700*1&w5-3423*1]  32"
    "[i7-13700*2]            32"
    "[i7-13700*1&w5-3423*1] 40"
)

for CONFIG in "${CONFIGS[@]}"; do
    CONSTRAINT=$(echo "$CONFIG" | awk '{print $1}')
    NTASKS=$(echo "$CONFIG" | awk '{print $2}')

    echo "Submitting $SCRIPT with constraint=$CONSTRAINT ntasks=$NTASKS"
    sbatch --constraint="$CONSTRAINT" --ntasks="$NTASKS" "$SCRIPT"
done
