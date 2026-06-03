#!/usr/bin/env bash
# ============================================================
# export-aseprite.sh
# Scanne récursivement les .aseprite et les exporte en images
#   - 1 frame → PNG
#   - > 1 frame → GIF animé
# Les images sont placées dans output/ en miroir de l'arborescence
# ============================================================
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(pwd)}"
OUTPUT_DIR="$REPO_ROOT/output"
ERRORS=0
TOTAL=0

mkdir -p "$OUTPUT_DIR"

echo "=== Scanning for .aseprite files... ==="

ASEPRITE_FILES=()
while IFS= read -r -d '' file; do
  ASEPRITE_FILES+=("$file")
done < <(find "$REPO_ROOT" -name "*.aseprite" -not -path '*/\.*' -print0)

if [ ${#ASEPRITE_FILES[@]} -eq 0 ]; then
  echo "[WARN] No .aseprite files found. Nothing to export."
  exit 0
fi

echo "Found ${#ASEPRITE_FILES[@]} .aseprite file(s)."
echo ""

# Vérifier que aseprite est disponible
if ! command -v aseprite &>/dev/null; then
  echo "[ERROR] 'aseprite' command not found in PATH."
  exit 1
fi

echo "[INFO] Aseprite version: $(aseprite --version 2>&1)"
echo ""

for aseprite_file in "${ASEPRITE_FILES[@]}"; do
  TOTAL=$((TOTAL + 1))
  filename=$(basename "$aseprite_file" .aseprite)
  relative_path="${aseprite_file#$REPO_ROOT/}"
  relative_dir=$(dirname "$relative_path")
  output_subdir="$OUTPUT_DIR/$relative_dir"

  mkdir -p "$output_subdir"

  echo "--- Processing: $relative_path ---"

  # 1) Déterminer le nombre de frames via le JSON de métadonnées
  tmp_dir=$(mktemp -d "$REPO_ROOT/.tmp-XXXXXX")
  frame_count=0

  if aseprite -b "$aseprite_file" \
    --data "$tmp_dir/frames.json" \
    --format json-array \
    --save-as "$tmp_dir/dummy.png" \
    2>&1; then
    if [ -f "$tmp_dir/frames.json" ]; then
      frame_count=$(jq '.frames | length' "$tmp_dir/frames.json" 2>/dev/null || echo "0")
    fi
  else
    echo "  [WARN] Aseprite could not read the file - see error above."
  fi

  rm -rf "$tmp_dir"

  # Si frame_count est vide ou nul, fallback direct PNG
  if [ -z "$frame_count" ] || [ "$frame_count" -le 0 ]; then
    echo "  [WARN] Frame count unknown, trying direct PNG export..."
    if aseprite -b "$aseprite_file" --save-as "$output_subdir/$filename.png" 2>&1; then
      echo "  [OK] Exported as PNG (fallback)"
    else
      echo "  [ERROR] Failed to export $relative_path - skipping"
      ERRORS=$((ERRORS + 1))
    fi
    continue
  fi

  # 2) Exporter selon le nombre de frames
  if [ "$frame_count" -eq 1 ]; then
    if aseprite -b "$aseprite_file" --save-as "$output_subdir/$filename.png" 2>&1; then
      echo "  [OK] Exported -> output/$relative_dir/$filename.png  (1 frame)"
    else
      echo "  [ERROR] PNG export failed for $relative_path"
      ERRORS=$((ERRORS + 1))
    fi
  else
    if aseprite -b "$aseprite_file" --save-as "$output_subdir/$filename.gif" 2>&1; then
      echo "  [OK] Exported -> output/$relative_dir/$filename.gif  ($frame_count frames)"
    else
      echo "  [ERROR] GIF export failed for $relative_path"
      ERRORS=$((ERRORS + 1))
    fi
  fi

  echo ""
done

echo "Summary: $TOTAL processed, $ERRORS errors"
echo "Output in: output/"

exit $ERRORS
