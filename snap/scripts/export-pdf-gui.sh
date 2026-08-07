#!/usr/bin/env bash

# Paperwork PDF Export GUI
# Works inside the Snap and outside (for testing)

# CLI: inside Snap → paperwork-cli | outside → snap command
if [ -n "$SNAP" ]; then
  CLI="paperwork-cli"
  export PATH="$SNAP/usr/bin:$SNAP/bin:$PATH"
else
  CLI="openpaperwork-snap.paperwork-cli"
fi

while true; do

  TODAY=$(date +%d.%m.%Y)

  RESULT=$(yad --form \
    --title="Paperwork → PDF Export" \
    --width=520 \
    --center \
    --window-icon=document-export \
    --field="Paperwork work directory:DIR" "$HOME/papers" \
    --field="Output directory:DIR" "$HOME/papers-export" \
    --field="Start date:DT" "$TODAY" \
    --field="End date:DT" "$TODAY" \
    --field="Tag 1:" "" \
    --field="Tag 2:" "" \
    --field="Tag 3:" "" \
    --field="Note: Tags are additive (OR) – more tags = more matches:LBL" "" \
    --button="Cancel:1" \
    --button="Export:0")

  [ $? -ne 0 ] && exit 0

  IFS='|' read -r WORK_DIR OUT_DIR START_DATE END_DATE TAG1 TAG2 TAG3 _NOTE <<< "$RESULT"

  TAG1=$(echo "$TAG1" | xargs)
  TAG2=$(echo "$TAG2" | xargs)
  TAG3=$(echo "$TAG3" | xargs)

  if [ ! -d "$WORK_DIR" ]; then
    yad --error --title="Error" --text="Work directory does not exist:\n$WORK_DIR" --button="OK:0"
    continue
  fi

  mkdir -p "$OUT_DIR"

  to_yyyymmdd() {
    local d="$1"
    if [[ "$d" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]]; then
      echo "${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
      return
    fi
    if [[ "$d" =~ ^[0-9]{8}$ ]]; then
      echo "$d"
      return
    fi
    if [[ "$d" =~ ^([0-9]{1,2})\.([0-9]{1,2})\.([0-9]{4})$ ]]; then
      printf "%04d%02d%02d" \
        "$((10#${BASH_REMATCH[3]}))" \
        "$((10#${BASH_REMATCH[2]}))" \
        "$((10#${BASH_REMATCH[1]}))"
      return
    fi
    date -d "$d" +%Y%m%d 2>/dev/null || echo "00000000"
  }

  START_NUM=$(to_yyyymmdd "$START_DATE")
  END_NUM=$(to_yyyymmdd "$END_DATE")

  DOC_IDS=""
  while IFS= read -r -d '' dir; do
    doc_id=$(basename "$dir")
    DOC_DATE=${doc_id:0:8}

    [[ "$DOC_DATE" =~ ^[0-9]{8}$ ]] || continue
    [[ "$DOC_DATE" -ge "$START_NUM" && "$DOC_DATE" -le "$END_NUM" ]] || continue

    # Tags are additive (OR)
    if [ -n "$TAG1$TAG2$TAG3" ]; then
      label_file="$dir/labels"
      [ -f "$label_file" ] || continue
      match=0
      for tag in "$TAG1" "$TAG2" "$TAG3"; do
        [ -z "$tag" ] && continue
        if grep -qiE "^${tag}(,|$)" "$label_file" 2>/dev/null; then
          match=1
          break
        fi
      done
      [ $match -eq 0 ] && continue
    fi

    DOC_IDS="${DOC_IDS}${doc_id}"$'\n'
  done < <(find "$WORK_DIR" -maxdepth 1 -type d \
           -name '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_*' -print0 2>/dev/null)

  DOC_IDS=$(echo "$DOC_IDS" | sed '/^$/d')

  if [ -z "$DOC_IDS" ]; then
    yad --info --title="No results" \
        --text="No documents found.\n\nWork dir: $WORK_DIR\nDate: $START_DATE → $END_DATE\n($START_NUM – $END_NUM)" \
        --button="OK:0"
    continue
  fi

  COUNT=$(echo "$DOC_IDS" | wc -l)

  yad --question \
    --title="Start export?" \
    --text="Found <b>$COUNT</b> document(s).\n\nWork directory:\n$WORK_DIR\n\nOutput directory:\n$OUT_DIR\n\nStart export now?" \
    --button="Cancel:1" \
    --button="Yes, export:0"

  [ $? -ne 0 ] && continue

  OK_COUNT=0
  FAIL_COUNT=0
  LOG=""

  while read -r doc_id; do
    [ -z "$doc_id" ] && continue

    label_file="$WORK_DIR/$doc_id/labels"
    labels=""
    if [ -f "$label_file" ]; then
      labels=$(cut -d, -f1 "$label_file" 2>/dev/null | tr '\n' '_' | sed 's/_$//' | tr -cd '[:alnum:]_-')
    fi

    if [ -z "$labels" ]; then
      filename="${doc_id}.pdf"
    else
      filename="${doc_id}__${labels}.pdf"
    fi

    out_file="$OUT_DIR/$filename"
    success=0
    method=""

    # --- 1) Paperwork CLI: searchable PDF ---
    if command -v "${CLI%% *}" >/dev/null 2>&1; then
      if $CLI export "$doc_id" -f automatic_pdf -o "$out_file" 2>/dev/null; then
        if [ -f "$out_file" ] && [ -s "$out_file" ]; then
          success=1
          method="cli/searchable"
        fi
      fi
    fi

    # --- 2) Fallback: existing doc.pdf ---
    if [ $success -eq 0 ] && [ -f "$WORK_DIR/$doc_id/doc.pdf" ]; then
      if cp "$WORK_DIR/$doc_id/doc.pdf" "$out_file"; then
        success=1
        method="copy"
      fi
    fi

    # --- 3) Fallback: img2pdf (image-only) ---
    if [ $success -eq 0 ]; then
      mapfile -t pages < <(find "$WORK_DIR/$doc_id" -maxdepth 1 \
        \( -name 'paper.*.png' -o -name 'paper.*.jpg' -o -name 'paper.*.jpeg' \) \
        ! -name '*.thumb.*' \
        2>/dev/null | sort -V)

      if [ ${#pages[@]} -gt 0 ] && command -v img2pdf >/dev/null 2>&1; then
        if img2pdf "${pages[@]}" -o "$out_file" 2>/dev/null; then
          if [ -f "$out_file" ] && [ -s "$out_file" ]; then
            success=1
            method="img2pdf"
          fi
        fi
      fi
    fi

    # --- 4) Fallback: ImageMagick ---
    if [ $success -eq 0 ]; then
      mapfile -t pages < <(find "$WORK_DIR/$doc_id" -maxdepth 1 \
        \( -name 'paper.*.png' -o -name 'paper.*.jpg' -o -name 'paper.*.jpeg' \) \
        ! -name '*.thumb.*' \
        2>/dev/null | sort -V)

      if [ ${#pages[@]} -gt 0 ] && command -v convert >/dev/null 2>&1; then
        if convert "${pages[@]}" "$out_file" 2>/dev/null; then
          if [ -f "$out_file" ] && [ -s "$out_file" ]; then
            success=1
            method="convert"
          fi
        fi
      fi
    fi

    if [ $success -eq 1 ]; then
      OK_COUNT=$((OK_COUNT + 1))
      LOG="${LOG}OK ($method) $filename\n"
      echo "OK   $filename ($method)"
    else
      FAIL_COUNT=$((FAIL_COUNT + 1))
      LOG="${LOG}FAIL $doc_id\n"
      echo "FAIL $doc_id"
    fi
  done <<< "$DOC_IDS"

  yad --info \
    --title="Finished" \
    --text="Done.\n\nOK:   $OK_COUNT\nFail: $FAIL_COUNT\n\nOutput:\n$OUT_DIR\n\n$LOG" \
    --button="Back to menu:0" \
    --button="Open folder:2" \
    --button="Quit:1"

  case $? in
    0) continue ;;
    2) xdg-open "$OUT_DIR" 2>/dev/null; continue ;;
    *) exit 0 ;;
  esac

done
