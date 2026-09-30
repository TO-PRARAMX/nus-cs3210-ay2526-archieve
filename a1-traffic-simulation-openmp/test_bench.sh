
#!/bin/bash

# Colors
RED="\033[0;31m"
GREEN="\033[0;32m"
CYAN="\033[0;36m"
RESET="\033[0m"

# --- Utilities ---
log() { echo -e "${2:-$RESET}${1}${RESET}"; }

# --- Specific Parameter Lists ---
Ns=(1000 2000 3000 5000 10000)
Ls_mults=(2 3 5 10 20)
Ps=(0.0 0.2 0.4 0.6 0.8 1.0)
POS_MODES=("random" "even")
VEL_MODES=("random" "zero")

ITERATIONS_PER_N=10  # Reasonable coverage without the wait
IN_PATH="inputs/in_tmp"

mkdir -p "inputs"
make > /dev/null 2>&1

for n in "${Ns[@]}"; do
    log "--- Testing N = $n ---" "$CYAN"

    for ((i=1; i<=ITERATIONS_PER_N; i++)); do
        # Pick from your specific requested values
        mult=${Ls_mults[$RANDOM % ${#Ls_mults[@]}]}
        L=$((mult * n))
        pstart=${Ps[$RANDOM % ${#Ps[@]}]}
        pdec=${Ps[$RANDOM % ${#Ps[@]}]}
        
        # Alternate/Pick modes
        pos=${POS_MODES[$RANDOM % ${#POS_MODES[@]}]}
        vel=${VEL_MODES[$RANDOM % ${#VEL_MODES[@]}]}
        
        # vmax stays slightly dynamic
        vmax=$(( (RANDOM % 36) + 5 ))

        printf "  [Iter %-2s] L=%-6s ps=%s pd=%s pos=%-6s vel=%-6s " \
               "$i" "$L" "$pstart" "$pdec" "$pos" "$vel"

        # Generate
        python3 gen.py --n "$n" --L "$L" --vmax "$vmax" \
            --p-dec "$pdec" --p-start "$pstart" --steps 500 \
            --pos "$pos" --vel "$vel" --seed "$RANDOM" \
            --out "$IN_PATH" > /dev/null 2>&1

        # Run & Compare
        ./sim.perf < "$IN_PATH" > OUT_MINE 2>&1
        ./executables/bench-5.perf < "$IN_PATH" > OUT_REF 2>&1

        if ! diff -q OUT_MINE OUT_REF > /dev/null; then
            log "\n💥 ERROR: Failed at N=$n (Iter $i)!" "$RED"
            log "Config: L=$L, ps=$pstart, pd=$pdec, pos=$pos, vel=$vel" "$RED"
            cp "$IN_PATH" "inputs/failed_N${n}_iter${i}.txt"
            exit 1
        fi
        
        echo -e "${GREEN}OK${RESET}"
    done
    echo ""
done

log "✨ TARGETED TESTS PASSED ✨" "$GREEN"
rm -f OUT_MINE OUT_REF
