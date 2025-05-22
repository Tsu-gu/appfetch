#!/bin/bash

OUT="snap_all_results.txt"
ALPHABET=({a..z})

echo "📦 Running snap searches..."
> "$OUT"

for letter in "${ALPHABET[@]}"; do
  echo "🔍 snap search $letter"
  echo "## snap search $letter" >> "$OUT"
  snap search "$letter" >> "$OUT"
  echo "" >> "$OUT"
done

echo "✅ Done. Saved to $OUT"

