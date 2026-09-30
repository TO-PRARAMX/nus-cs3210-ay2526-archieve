#!/bin/bash

# Check if a filename was provided as an argument
if [ -z "$1" ]; then
  echo "Usage: $0 <filename>"
  exit 1
fi

FILE="$1"

# Check if the file exists
if [ ! -f "$FILE" ]; then
    echo "Error: File '$FILE' not found."
    exit 1
fi

# Find the line number using grep and cut
# -n prints the line number
# -E enables extended regular expressions to handle the flexible whitespace (\s+)
grep -nE "Avg\. Active Threads Per Warp\s+14\.51" "$FILE" | cut -d: -f1