#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(pwd)}"
OUTPUT_DIR="$REPO_ROOT/output"
ERRORS=0
TOTAL=0

mkdir -p "$OUTPUT_DIR"

echo "Scanning for .aseprite files..."

ASEPRITE_FILES=()
while IFS= read -r -d '' file; do
  ASEPRITE_FILES+=("$file")
done < <(find "$REPO_ROOT" -name "*.aseprite" -not -path '*/\.*' -print0)

if [ ${#ASEPRITE_FILES[@]} -eq 0 ]; then
  echo "No .aseprite files found. Nothing to export."
  exit 0
fi

echo "Found ${#ASEPRITE_FILES[@]} .aseprite file(s)."
echo ""

for aseprite_file in "${ASEPRITE_FILES[@]}"; do
  TOTAL=$((TOTAL + 1))
  filename=$(basename "$aseprite_file" .aseprite)
  relative_path="${aseprite_file#$REPO_ROOT/}"
  relative_dir=$(dirname "$relative_path")
  output_subdir="$OUTPUT_DIR/$relative_dir"

  mkdir -p "$output_subdir"

  echo "Processing: $relative_path"

  tmp_dir=$(mktemp -d "$REPO_ROOT/.tmp-XXXXXX")
  frame_count=0

  if aseprite -b "$aseprite_file" \
    --data "$tmp_dir/frames.json" \
    --format json-array \
    --save-as "$tmp_dir/dummy.png" \
    2>/dev/null; then

    if [ -f "$tmp_dir/frames.json" ]; then
      frame_count=$(jq '.frames | length' "$tmp_dir/frames.json" 2>/dev/null || echo "0")
    fi
  else
    echo " Could not read metadata (file may be damaged or empty)"
  fi

  rm -rf "$tmp_dir"

  if [ -z "$frame_count" ] || [ "$frame_count" -le 0 ]; then
    echo "  Could not determine frame count, trying direct export..."
    if aseprite -b "$aseprite_file" --save-as "$output_subdir/$filename.png" 2>/dev/null; then
      echo "  Exported as PNG (fallback)"
    else
      echo "  Failed to export $relative_path — skipping"
      ERRORS=$((ERRORS + 1))
    fi
    continue
  fi

  if [ "$frame_count" -eq 1 ]; then
    if aseprite -b "$aseprite_file" --save-as "$output_subdir/$filename.png" 2>/dev/null; then
      echo "  Exported -> output/$relative_dir/$filename.png  (1 frame)"
    else
      echo "  PNG export failed for $relative_path"
      ERRORS=$((ERRORS + 1))
    fi
  else
    if aseprite -b "$aseprite_file" --save-as "$output_subdir/$filename.gif" 2>/dev/null; then
      echo "  Exported -> output/$relative_dir/$filename.gif  ($frame_count frames)"
    else
      echo "  GIF export failed for $relative_path"
      ERRORS=$((ERRORS + 1))
    fi
  fi

  echo ""
done

echo "Summary: $TOTAL processed, $ERRORS errors"
echo "Output in: output/"

exit $ERRORS
