import subprocess
import os
import random
import time
import sys
import re

# --- Colors & Config ---
G, R, Y, B, C, M, BOLD, END = '\033[92m', '\033[91m', '\033[93m', '\033[94m', '\033[96m', '\033[95m', '\033[1m', '\033[0m'

# Test Parameters
D, Q, A = 100000, 100000, 32
K = 1000
TASKS_TO_TEST = [12, 16, 18, 24, 32]

MY_ENGINE = "./engine"
REF_ENGINE = "./benchmarks/bench_4"
INPUT_FILE = "scaling_test.bin"

# distribute across two nodes (harder)
def run_bench(engine, n_tasks, label):
    """Runs engine, greps 'Time taken', and returns (duration_in_seconds, sorted_output_lines)"""
    with open(INPUT_FILE, 'rb') as f_in:
        result = subprocess.run(
            ["srun", "-N2", "-n", str(n_tasks), f"--ntasks-per-node={int(n_tasks/2)}", "--nodelist=soctf-pdc-035,soctf-pdc-036", "--input=0",
             "--time=00:02:00", engine],
            stdin=f_in, 
            capture_output=True,
            text=True
        )
    
    if result.returncode != 0:
        print(result.stderr)
        return None, None

    # Search for "Time taken: XXX ms" in stdout
    match = re.search(r"Time taken:\s*(\d+)\s*ms", result.stderr)
    if match:
        # Convert ms string to float seconds
        duration = float(match.group(1)) / 1000.0
    else:
        # Fallback to 0 if not found, or use a wall-clock if preferred
        duration = 0.0
        
    # Standardise output for comparison: ignore the "Time taken" line itself
    # and srun info lines to ensure only result lines are compared
    clean_lines = [l for l in result.stdout.splitlines() if "Time taken" not in l and "srun:" not in l]
    
    return duration, sorted(clean_lines)

def main():
    print(f"{BOLD}{B}=== KNN MPI SCALING BENCHMARK ==={END}")
    print(f"Config: D={D}, Q={Q}, A={A}, K={K}\n")

    # 1. Generate the single test case
    print(f"{M}Generating shared input file...{END}", end=" ", flush=True)
    subprocess.run([
        "python3", "generate_input.py", 
        "--num_data", str(D), "--num_queries", str(Q), "--num_attrs", str(A), 
        "--min", "1", "--max", "1000000", "--minK", str(K), "--maxK", str(K), 
        "--num_labels", "100", "--output", INPUT_FILE
    ], check=True)
    print(f"{G}Done.{END}\n")

    print(f"{BOLD}{'Tasks':<8} | {'My Engine':<12} | {'Ref Engine':<12} | {'Diff':<10} | {'Status'}{END}")
    print("-" * 65)

    for n in TASKS_TO_TEST:
        my_time, my_out = run_bench(MY_ENGINE, n, "MINE")
        ref_time, ref_out = run_bench(REF_ENGINE, n, "REF")

        if my_time is None or ref_time is None:
            print(f"{n:<8} | {R}CRASHED{END}")
            continue

        match = (my_out == ref_out)
        status = f"{G}PASS ✓{END}" if match else f"{R}FAIL ✗{END}"
        
        # Calculate percentage difference based on engine-reported ms
        if ref_time > 0:
            diff_pct = ((my_time / ref_time) - 1) * 100
        else:
            diff_pct = 0.0
        
        diff_color = R if diff_pct > 10 else (G if diff_pct < -5 else Y)
        
        print(f"{n:<8} | {my_time:>10.3f}s | {ref_time:>10.3f}s | {diff_color}{diff_pct:>+8.1f}%{END} | {status}")

    if os.path.exists(INPUT_FILE): os.remove(INPUT_FILE)
    print(f"\n{BOLD}{B}Benchmark Complete.{END}")

if __name__ == "__main__":
    main()
