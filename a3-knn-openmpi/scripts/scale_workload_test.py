import subprocess
import os
import re
import itertools

# --- Colors & Config ---
G, R, Y, B, C, M, BOLD, END = '\033[92m', '\033[91m', '\033[93m', '\033[94m', '\033[96m', '\033[95m', '\033[1m', '\033[0m'

# Fixed Hardware Parameters
N_TASKS = 16
NODE_LIST = "soctf-pdc-040"
NODES_COUNT = "1"

# Scaling Workload Parameters
D_VALS = [100000]
Q_VALS = [40000, 80000, 120000, 160000, 200000]
A_VALS = [10]

# This generates all 27 combinations (Cartesian Product)
TEST_CASES = list(itertools.product(D_VALS, Q_VALS, A_VALS))

MY_ENGINE = "./engine"
REF_ENGINE = "./benchmarks/bench_4"
INPUT_FILE = "scaling_test.bin"

def run_bench(engine, n_tasks, label):
    """Runs engine on a single node (040) and returns duration and output."""
    with open(INPUT_FILE, 'rb') as f_in:
        result = subprocess.run(
            [
                "srun", 
                f"-N{NODES_COUNT}", 
                "-n", str(n_tasks), 
                f"--nodelist={NODE_LIST}", 
                "--input=0", 
                "--time=00:05:00", 
                engine
            ],
            stdin=f_in, 
            capture_output=True,
            text=True
        )
    
    if result.returncode != 0:
        return None, None

    # Search for "Time taken: XXX ms"
    match = re.search(r"Time taken:\s*(\d+)\s*ms", result.stderr)
    duration = float(match.group(1)) / 1000.0 if match else 0.0
        
    clean_lines = [l for l in result.stdout.splitlines() if "Time taken" not in l and "srun:" not in l]
    return duration, sorted(clean_lines)

def main():
    print(f"{BOLD}{B}=== KNN FULL COMBINATORIAL BENCHMARK ==={END}")
    print(f"Node: {NODE_LIST} | Tasks: {N_TASKS} | Total Cases: {len(TEST_CASES)}\n")
    
    header = f"{BOLD}{'D':>6} {'Q':>6} {'A':>4} | {'My Engine':>12} | {'Ref Engine':>12} | {'Diff':>10} | {'Status'}{END}"
    print(header)
    print("-" * len(header))

    for d, q, a in TEST_CASES:
        # 1. Generate specific input for this combination
        # Using capture_output=True to keep the terminal clean
        subprocess.run([
            "python3", "generate_input.py", 
            "--num_data", str(d), "--num_queries", str(q), "--num_attrs", str(a), 
            "--min", "1", "--max", "1000000", "--minK", "1000", "--maxK", "1000", 
            "--num_labels", "100", "--output", INPUT_FILE
        ], check=True, capture_output=True)

        # 2. Run Engines
        my_time, my_out = run_bench(MY_ENGINE, N_TASKS, "MINE")
        ref_time, ref_out = run_bench(REF_ENGINE, N_TASKS, "REF")

        if my_time is None or ref_time is None:
            print(f"{d:>6} {q:>6} {a:>4} | {R}CRASHED/TIMEOUT{END}")
            continue

        # 3. Stats & Formatting
        match = (my_out == ref_out)
        status = f"{G}PASS ✓{END}" if match else f"{R}FAIL ✗{END}"
        
        if ref_time > 0:
            diff_pct = ((my_time / ref_time) - 1) * 100
        else:
            diff_pct = 0.0
        
        diff_color = R if diff_pct > 10 else (G if diff_pct < -5 else Y)
        
        print(f"{d:>6} {q:>6} {a:>4} | {my_time:>10.3f}s | {ref_time:>10.3f}s | {diff_color}{diff_pct:>+8.1f}%{END} | {status}")

    # Cleanup
    if os.path.exists(INPUT_FILE): 
        os.remove(INPUT_FILE)
    print(f"\n{BOLD}{B}Benchmark Complete.{END}")

if __name__ == "__main__":
    main()
