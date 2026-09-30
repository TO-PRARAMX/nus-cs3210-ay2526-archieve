threads=1
dir="raw-data/number-of-thread"

for f in "$dir"/*; do
  [[ -f "$f" ]] || continue
  awk -v t="$threads" '
    /partition:/ {
      print
      if (getline nextline) {
        if (nextline !~ /^number of threads:[[:space:]]*/) print "number of threads:" t
        print nextline
        next
      } else {
        print "number of threads: " t
        next
      }
    }
    { print }
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done