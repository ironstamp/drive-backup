#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Google Drive -> local backup, converting Google files to Office formats.
#   Docs -> .docx   Sheets -> .xlsx   Slides -> .pptx   Drawings -> .svg
#
# 1. Copies ALL of My Drive into  $DEST/My Drive
#    (except anything matched in excludes.txt, e.g. the Classroom folder)
# 2. Copies each item listed in shared_items.txt into
#    $DEST/Shared drives/<Label>/<path>   (or $DEST/My Drive/<path> for "mydrive" lines)
#
# Usage:   ./backup_drive.sh                (real run)
#          ./backup_drive.sh --dry-run      (show what would be copied, copy nothing)
#          ./backup_drive.sh --shared-only  (skip My Drive, only do shared_items.txt)
#          (the two options can be combined)
#
# Safe to re-run: rclone only fetches new/changed files and never deletes
# anything locally.
# ---------------------------------------------------------------------------
set -uo pipefail

# ---- Settings -------------------------------------------------------------
REMOTE="gdrive"                              # name you gave in `rclone config`
DEST="${HOME}/DriveBackup"                   # where the backup goes
HERE="$(cd "$(dirname "$0")" && pwd)"
LIST="$HERE/shared_items.txt"
EXCLUDES="$HERE/excludes.txt"           # folders to skip in My Drive
FORMATS="docx,xlsx,pptx,svg"
# ---------------------------------------------------------------------------

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

mkdir -p "$DEST"
LOG="$DEST/backup_$(date +%Y%m%d_%H%M%S).log"

COMMON=(
  --drive-export-formats "$FORMATS"
  --drive-skip-shortcuts          # don't pull in files that are only shortcuts
  --transfers 4 --checkers 8 --tpslimit 10
  --progress
  --log-file "$LOG" --log-level INFO
)
SHARED_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run)     COMMON+=(--dry-run); echo ">>> DRY RUN - nothing will be copied" ;;
    --shared-only) SHARED_ONLY=1 ;;
    *) echo "Unknown option: $arg"; exit 2 ;;
  esac
done

failures=0

# ---- 1. My Drive ----------------------------------------------------------
if (( SHARED_ONLY )); then
  echo ">>> Skipping My Drive (--shared-only)"
else
echo ">>> Backing up My Drive -> $DEST/My Drive"
EXCL=(); [[ -f "$EXCLUDES" ]] && EXCL=(--exclude-from "$EXCLUDES") && echo "    (skipping paths listed in excludes.txt)"
if ! rclone copy "${REMOTE}:" "$DEST/My Drive" "${COMMON[@]}" ${EXCL[@]+"${EXCL[@]}"}; then
  echo "!!! My Drive backup reported errors (see log)"; failures=$((failures+1))
fi
fi

# ---- 2. Selected shared-drive items ---------------------------------------
if [[ -f "$LIST" ]]; then
  while IFS='|' read -r id label path || [[ -n "${id:-}" ]]; do
    id="$(trim "${id:-}")"; label="$(trim "${label:-}")"; path="$(trim "${path:-}")"
    [[ -z "$id" || "$id" == \#* ]] && continue
    [[ -z "$label" ]] && label="$id"

    if [[ "$(printf %s "$id" | tr "[:upper:]" "[:lower:]")" == "mydrive" ]]; then
      src="${REMOTE}:${path}"; base="$DEST/My Drive"        # item from your own Drive
    else
      src="${REMOTE},team_drive=${id}:${path}"; base="$DEST/Shared drives/$label"
    fi

    # Work out whether the item is a folder or a single file
    is_dir=1
    if [[ -n "$path" ]]; then
      stat="$(rclone lsjson --stat "$src" --drive-export-formats "$FORMATS" 2>/dev/null)"
      if [[ -z "$stat" ]]; then
        echo "!!! Not found: [$label] $path  (check the exact name with rclone lsf)"
        failures=$((failures+1)); continue
      fi
      grep -q '"IsDir":true' <<<"$stat" || is_dir=0
    fi

    if (( is_dir )); then
      dest="$base/$path"
    else
      parent="$(dirname "$path")"; [[ "$parent" == "." ]] && parent=""
      dest="$base/$parent"
    fi

    echo ">>> [$label] ${path:-<whole drive>} -> $dest"
    if ! rclone copy "$src" "$dest" "${COMMON[@]}"; then
      echo "!!! Errors copying [$label] $path (see log)"; failures=$((failures+1))
    fi
  done < "$LIST"
else
  echo ">>> No shared_items.txt found - skipping shared drives"
fi

echo
if (( failures )); then
  echo "Finished with $failures problem(s). Log: $LOG"; exit 1
else
  echo "All done. Log: $LOG"
fi
