#!/usr/bin/env bash
# ============================================================
# generate-readme.sh
# Génère le README.md galerie à partir des images dans output/
# ============================================================
set -euo pipefail

trap 'echo "[ERROR] at line $LINENO (exit: $?)" >&2' ERR

REPO_ROOT="${REPO_ROOT:-$(pwd)}"
OUTPUT_DIR="$REPO_ROOT/output"
README="$REPO_ROOT/README.md"

echo "[DEBUG] REPO_ROOT=$REPO_ROOT"
echo "[DEBUG] PWD=$(pwd)"
echo "[DEBUG] shell=$(ps -p $$ -o comm=)"

# Test sort -V
if echo -e 'day1\nday10\nday2' | sort -V >/dev/null 2>&1; then
  echo "[DEBUG] sort -V works"
  SORT_CMD="sort -V"
else
  echo "[DEBUG] sort -V NOT available, using -n"
  SORT_CMD="sort -t'd' -k2 -n"
fi

total_sprites=0
total_frames=0
day_count=0

days_content=""

get_frame_count() {
  local aseprite_file="$1"
  local tmp_dir
  tmp_dir=$(mktemp -d "$REPO_ROOT/.tmp-XXXXXX")
  local count=0

  if aseprite -b "$aseprite_file" \
    --data "$tmp_dir/info.json" \
    --format json-array \
    --save-as "$tmp_dir/d.png" \
    2>/dev/null && [ -f "$tmp_dir/info.json" ]; then
    count=$(jq '.frames | length' "$tmp_dir/info.json" 2>/dev/null || echo "0")
  fi

  rm -rf "$tmp_dir"
  echo "${count:-0}"
}

get_image_dimensions() {
  local img="$1"
  if command -v identify &>/dev/null && [ -f "$img" ]; then
    identify -format "%w %h" "$img" 2>/dev/null || echo "0 0"
  else
    echo "0 0"
  fi
}

compute_display_size() {
  local sprite_count="$1"
  local width="$2"
  local height="$3"

  local max_size
  if [ "$sprite_count" -le 1 ]; then
    max_size=300
  else
    max_size=200
  fi

  if [ "$width" -gt 0 ] && [ "$height" -gt 0 ]; then
    local ratio
    ratio=$(echo "scale=2; $width / $height" | bc 2>/dev/null || echo "1")
    if (( $(echo "$ratio > 3" | bc -l 2>/dev/null) )); then
      max_size=$((max_size * 2 / 3))
    elif (( $(echo "$ratio < 0.33" | bc -l 2>/dev/null) )); then
      max_size=$((max_size * 2 / 3))
    fi
  fi

  echo "$max_size"
}

echo "Scanning day folders..."

day_dirs=()
while IFS= read -r dir; do
  day_dirs+=("$dir")
done < <(find "$REPO_ROOT" -maxdepth 1 -type d -name 'day*' | $SORT_CMD)

echo "[DEBUG] found ${#day_dirs[@]} day dirs: ${day_dirs[*]:-(none)}"

if [ ${#day_dirs[@]} -eq 0 ]; then
  echo "No day folders found. Generating minimal README."
fi

for day_dir in "${day_dirs[@]}"; do
  day_name=$(basename "$day_dir")
  day_count=$((day_count + 1))

  aseprite_files=()
  while IFS= read -r f; do
    aseprite_files+=("$f")
  done < <(find "$day_dir" -maxdepth 1 -name '*.aseprite' | sort)

  if [ ${#aseprite_files[@]} -eq 0 ]; then
    continue
  fi

  output_day_dir="$OUTPUT_DIR/$day_name"
  mkdir -p "$output_day_dir"

  day_sprites=0
  day_frames=0
  day_rows=""       # HTML rows pour ce jour
  sprite_names=""   # Liste des noms pour le titre

  for aseprite_file in "${aseprite_files[@]}"; do
    base=$(basename "$aseprite_file" .aseprite)
    frame_count=$(get_frame_count "$aseprite_file")
    [ -z "$frame_count" ] && frame_count=0

    if [ "$frame_count" -gt 0 ]; then
      day_frames=$((day_frames + frame_count))
    fi

    img_file="$output_day_dir/$base.png"
    if [ ! -f "$img_file" ]; then
      img_file="$output_day_dir/$base.gif"
    fi

    if [ ! -f "$img_file" ]; then
      echo "  Image not found for $base - skipping in README"
      continue
    fi

    img_rel_path="output/$day_name/$base"
    if [[ "$img_file" == *.gif ]]; then
      img_rel_path="$img_rel_path.gif"
    else
      img_rel_path="$img_rel_path.png"
    fi

    echo "[DEBUG] img_file=$img_file"
    echo "[DEBUG] running get_image_dimensions output:"
    get_image_dimensions "$img_file" || echo "(get_image_dimensions returned non-zero)"
    echo "[DEBUG] identify available: $(command -v identify || echo NOT_FOUND)"

    read img_w img_h < <(get_image_dimensions "$img_file") || true
    echo "[DEBUG] read result: img_w=$img_w img_h=$img_h"
    [ "$img_w" -le 0 ] && img_w=16
    [ "$img_h" -le 0 ] && img_h=16

    if [ "$frame_count" -le 0 ]; then
      frame_label="? frames"
    elif [ "$frame_count" -eq 1 ]; then
      frame_label="1 frame"
    else
      frame_label="$frame_count frames"
    fi

    label_escaped="${base//&/&amp;}"
    label_escaped="${label_escaped//</&lt;}"
    label_escaped="${label_escaped//>/&gt;}"
    label_escaped="${label_escaped//\"/&quot;}"

    [ -n "$sprite_names" ] && sprite_names="$sprite_names, "
    sprite_names="${sprite_names}${label_escaped}"

    day_sprites=$((day_sprites + 1))

    # On utilise un format simple: TYPE|IMG_PATH|W|H|LABEL
    entry_label="${label_escaped} - ${frame_label}"
    if [ -z "$day_rows" ]; then
      day_rows="PNG_GIF|$img_rel_path|$img_w|$img_h|$entry_label"
    else
      day_rows="$day_rows
PNG_GIF|$img_rel_path|$img_w|$img_h|$entry_label"
    fi
  done

  # Mettre à jour les stats globales
  total_sprites=$((total_sprites + day_sprites))
  total_frames=$((total_frames + day_frames))

  if [ $day_sprites -eq 0 ]; then
    continue
  fi

  section_header="## Jour ${day_count} - ${sprite_names}"

  if [ "$day_sprites" -eq 1 ]; then
    while IFS='|' read -r _ img_rel_path img_w img_h label; do
      max_size=$(compute_display_size 1 "$img_w" "$img_h")
      day_html="
<p align=\"center\">
  <a href=\"${img_rel_path}\">
    <img src=\"${img_rel_path}\" width=\"${max_size}\" alt=\"${label}\">
  </a>
  <br>
  <em>${label}</em>
</p>"
    done <<< "$day_rows"
  else
    day_html="
<table>"

    cells=()
    while IFS='|' read -r _ img_rel_path img_w img_h label; do
      max_size=$(compute_display_size "$day_sprites" "$img_w" "$img_h")
      cells+=("<td align=\"center\">
  <a href=\"${img_rel_path}\">
    <img src=\"${img_rel_path}\" width=\"${max_size}\" alt=\"${label}\">
  </a>
  <br>
  <em>${label}</em>
</td>")
    done <<< "$day_rows"

    cols_per_row=4
    cell_count=${#cells[@]}
    for ((i=0; i<cell_count; i+=cols_per_row)); do
      day_html+="
  <tr>"
      for ((j=i; j<i+cols_per_row && j<cell_count; j++)); do
        day_html+="
    ${cells[$j]}"
      done
      day_html+="
  </tr>"
    done

    day_html+="
</table>"
  fi

  days_content+="
$section_header
$day_html

---

"
done

GEN_DATE=$(date -u "+%d %B %Y à %H:%M UTC")

cat > "$README" << README_HEADER
# 🎨 PixelArtJourney

Pixel arts quotidiens - Sprites créés avec [Aseprite](https://www.aseprite.org/).

**${total_sprites} sprites • ${day_count} jours • ${total_frames} frames au total**

Dernière mise à jour : ${GEN_DATE}

---

README_HEADER

# Ajouter le contenu des jours
echo "$days_content" >> "$README"

# Ajouter le pied de page
cat >> "$README" << README_FOOTER

*Généré automatiquement par [GitHub Actions](https://github.com/features/actions)*
README_FOOTER

echo ""
echo "README.md generated!"
echo "   $README"
echo "     $total_sprites sprites across $day_count days"
echo "     $total_frames total frames"
