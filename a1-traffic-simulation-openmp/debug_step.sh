#!/bin/bash
INPUT=$1
STEP=$2

echo "DEBUGSTEP RUNNING" >&2

if [[ -z "$STEP" ]]; then
    echo "Usage: $0 <file | -> <step>"
    exit 1
fi

START=$((STEP-1))
END=$((STEP+1))

# choose input source
if [[ "$INPUT" == "-" ]]; then
    SRC="/dev/stdin"
else
    SRC="$INPUT"
fi

awk -v start="$START" -v end="$END" '
/^Epoch:[[:space:]]*[0-9]+/ {
    match($0, /Epoch:[[:space:]]*([0-9]+)/, arr);
    epoch = arr[1];
}
' "$SRC