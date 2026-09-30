#!/usr/bin/env bash
set -euo pipefail

marker='USER EXECUTABLE PERFORMANCE STATISTICS'

mkdir -p csv

header='input_name,partition,execution_time,execution_time_error,LLC_loads,LLC_loads_error,LLC_load_misses,LLC_load_misses_error'
out="csv/raw.csv"

# helpers
val1() { # val1 <file> <regex>
  awk '/seconds time elapsed/ {print $1; exit}' "$1"
}
errp1() { # errp <file> <regex>   -> extracts the "+- xx%" number (xx)
  awk '
    /seconds time elapsed/ {
      if (match($0, /\(\s*\+\-[[:space:]]*([0-9.]+)%\s*\)/, a)) print a[1];
      else print "";
      exit
    }' "$1"
}

val2(){
  awk -v re="$2" '
  $0 ~ re && $1 !~ /</ {
    gsub(/,/, "", $1);
    print $1;
    exit
  }' "$1"
}

errp2() {
  awk -v re="$2" '
    $0 ~ re && $1 !~ /</{
      if (match($0, /\+\-[[:space:]]*([0-9.]+)%/, a)) print a[1];
      else print "";
      exit
    }' "$1"
}

declare -A wrote_header=()

while IFS= read -r -d '' file; do
  echo gurt
  grep -Fq "$marker" "$file" || continue

  # Extract "input file ..." (strips optional < >)
  input="$(
    awk '
      /input file/ {
        sub(/^.*input file:[[:space:]]+/, "");
        gsub(/[<>]/, "");
        print;
        exit
      }' "$file"
  )"
  partition="$(
    awk '
      /partition/ {
        sub(/^.*partition:[[:space:]]+/, "");
        gsub(/[<>]/, "");
        print;
        exit
      }' "$file"
  )"
  [[ -n "$input" ]] || input="unknown_input"

  safe="$(printf '%s' "$input" | sed 's/[^A-Za-z0-9._-]/_/g')"

  if [[ -z "${wrote_header[$out]:-}" ]]; then
    echo "$header" > "$out"
    wrote_header[$out]=1
  fi

  execution_time="$(val1 "$file" 'seconds time elapsed')"
  execution_time_error="$(errp1 "$file" 'seconds time elapsed')"

  LLC="$(val2 "$file" 'LLC-load')"
  LLC_ERR="$(errp2 "$file" 'LLC-load')"

  LLC_MISSES="$(val2 "$file" 'LLC-load-misses')"
  LLC_MISSES_ERR="$(errp2 "$file" 'LLC-load-misses')"

  echo -e "$input,$partition,$execution_time,$execution_time_error,$LLC,$LLC_ERR,$LLC_MISSES,$LLC_MISSES_ERR" >> "$out"
done < <(find raw-data -maxdepth 1 -type f -print0)

tmp=$(mktemp)
{
  head -n 1 "$out"
  tail -n +2 "$out" | sort -t',' -k1,1
} > "$tmp" && mv "$tmp" "$out"