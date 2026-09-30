import subprocess
import os
import random
import time
import sys

# --- Colors ---
G = '\033[92m'
R = '\033[91m'
Y = '\033[93m'
B = '\033[94m'
C = '\033[96m'
M = '\033[95m'
BOLD = '\033[1m'
END = '\033[0m'

# --- Configuration ---
NUM_TESTS = 10
NUM_RUNS = 1  # Number of runs to average
NUM_DATAS = [1000, 3000, 5000]
NUM_QUERIES = [1000, 3000, 5000]
NUM_ATTRS = [32, 100, 500]
NUM_TASKS_RANGE = list(range(10, 25))
MIN, MAX = 1, 1000000
MINK, MAXK = 10, 100
NUM_LABELS = 100

MY_ENGINE = "./engine"
REF_ENGINE = "./benchmarks/bench_4"
INPUT_FILE = "failed_input.bin"
MY_OUTPUT = "OUT_MINE"
REF_OUTPUT = "OUT_REF"


def run_engine(label, n_tasks, engine, input_file, output_file):
    """Run an engine NUM_RUNS times, verify output is consistent, return (durations, success)."""
    durations = []
    first_output = None

    for run_idx in range(NUM_RUNS):
        print(f"{C}│{END} {M}  [{label}] Run {run_idx+1}/{NUM_RUNS}...{END}   ", end="\r")
        start = time.time()
        with open(input_file, 'rb') as f_in, open(output_file, 'w') as f_out:
            result = subprocess.run(
                ["srun", "-n", str(n_tasks), "--nodelist=soctf-pdc-030,soctf-pdc-031",
                 "--input=0", "--time=00:05:00", engine],
                stdin=f_in, stdout=f_out
            )
        durations.append(time.time() - start)

        if result.returncode != 0:
            print(f"{C}│{END} {R}  [{label}] Run {run_idx+1} failed (exit {result.returncode}){END}")
            return None, False

        with open(output_file, 'r') as f:
            output = sorted(f.readlines())

        if first_output is None:
            first_output = output
        elif output != first_output:
            print(f"{C}│{END} {R}  [{label}] Run {run_idx+1} output differs from Run 1! Non-deterministic?{END}")
            return None, False

    avg = sum(durations) / len(durations)
    mn  = min(durations)
    mx  = max(durations)
    print(f"{C}│{END} {G}  [{label}] ✔ {NUM_RUNS} runs done{END} | avg={Y}{avg:.2f}s{END} min={Y}{mn:.2f}s{END} max={Y}{mx:.2f}s{END}")
    return first_output, True


def run_single_test(test_id):
    d = random.choice(NUM_DATAS)
    q = random.choice(NUM_QUERIES)
    a = random.choice(NUM_ATTRS)
    n_tasks = random.choice(NUM_TASKS_RANGE)

    print(f"{BOLD}{C}┌── TEST {test_id+1}/{NUM_TESTS}{END}")
    print(f"{C}│{END} {BOLD}CONFIG:{END} D={Y}{d}{END}, Q={Y}{q}{END}, A={Y}{a}{END}, Tasks={M}{n_tasks}{END}")

    success = False
    try:
        # 1. Generate Input
        subprocess.run([
            "python3", "generate_input.py",
            "--num_data", str(d), "--num_queries", str(q), "--num_attrs", str(a),
            "--min", str(MIN), "--max", str(MAX), "--minK", str(MINK),
            "--maxK", str(MINK), "--num_labels", str(NUM_LABELS),
            "--output", INPUT_FILE, "--seed", str(random.randint(0, 99999))
        ], check=True, capture_output=True)

        # 2. Run YOUR engine NUM_RUNS times
        print(f"{C}│{END} {M}Running Your Engine ({n_tasks} tasks, {NUM_RUNS}x)...{END}")
        mine_output, mine_ok = run_engine("Mine", n_tasks, MY_ENGINE, INPUT_FILE, MY_OUTPUT)
        if not mine_ok:
            print(f"{C}└──{END}")
            return False

        # 3. Run REFERENCE engine NUM_RUNS times
        print(f"{C}│{END} {M}Running Reference Engine ({n_tasks} tasks, {NUM_RUNS}x)...{END}")
        ref_output, ref_ok = run_engine("Ref", n_tasks, REF_ENGINE, INPUT_FILE, REF_OUTPUT)
        if not ref_ok:
            print(f"{C}└──{END}")
            return False

        # 4. Compare final outputs
        if mine_output == ref_output:
            print(f"{C}│{END} {G}RESULT: PASS ✓{END}")
            print(f"{C}└──{END}")
            success = True
        else:
            print(f"{C}│{END} {R}RESULT: FAIL (Output Mismatch){END}")
            print(f"{C}│{END} {Y}Keeping files: {INPUT_FILE}, {MY_OUTPUT}, {REF_OUTPUT}{END}")
            print(f"{C}└──{END}")

    except Exception as e:
        print(f"{C}│{END} {R}ERROR: {e}{END}")
        print(f"{C}└──{END}")

    if success:
        for f in [INPUT_FILE, MY_OUTPUT, REF_OUTPUT]:
            if os.path.exists(f): os.remove(f)

    return success


if __name__ == "__main__":
    os.system('clear')
    print(f"{BOLD}{B}=== KNN MPI TEST SUITE STARTING ==={END}\n")

    passed_count = 0
    start_suite = time.time()

    for i in range(NUM_TESTS):
        if not run_single_test(i):
            print(f"\n{BOLD}{R}🛑 CRITICAL FAILURE DETECTED. STOPPING SUITE.{END}")
            break
        passed_count += 1

    total_duration = time.time() - start_suite

    print(f"\n{BOLD}{B}" + "═"*40 + f"{END}")
    status_color = G if passed_count == NUM_TESTS else R
    print(f"{BOLD}TOTAL SCORE: {status_color}{passed_count}/{NUM_TESTS} PASSED{END}")
    if passed_count < NUM_TESTS:
        print(f"{BOLD}{Y}Check {MY_OUTPUT} and {REF_OUTPUT} to debug.{END}")
    print(f"{BOLD}TOTAL TIME:  {total_duration:.2f} seconds{END}")
    print(f"{BOLD}{B}" + "═"*40 + f"{END}\n")