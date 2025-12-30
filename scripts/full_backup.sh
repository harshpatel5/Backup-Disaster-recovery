#!/usr/bin/env bash
# Full backup script
# Usage: ./full_backup.sh [optional-destination-dir]
set -uo pipefail
IFS=$'\n\t'

# Load config if exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/config/backup.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

DEST="${1:-${BACKUP_DEST:-/var/backups/sofe3200_backups}}"
if ! mkdir -p "$DEST" 2>/dev/null; then
    echo "[ERROR] Unable to create backup destination '$DEST'. Check that the path exists and that you have write permissions." >&2
    exit 1
fi
if [[ ! -w "$DEST" ]]; then
    echo "[ERROR] Backup destination '$DEST' is not writable. Choose a location you can write to (for example a mounted external drive)." >&2
    exit 1
fi
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ARCHIVE_NAME="full_backup_${TIMESTAMP}.tar"
case "${COMPRESSION:-gzip}" in
  gzip) ARCHIVE="${ARCHIVE_NAME}.gz"; COMP_CMD=(gzip -c) ;;
  bzip2) ARCHIVE="${ARCHIVE_NAME}.bz2"; COMP_CMD=(bzip2 -c) ;;
  none) ARCHIVE="${ARCHIVE_NAME}"; COMP_CMD=(cat) ;;
  *) ARCHIVE="${ARCHIVE_NAME}.gz"; COMP_CMD=(gzip -c) ;;
esac

ARCHIVE_PATH="$DEST/$ARCHIVE"
LOG_FILE="${LOG_FILE:-$DEST/backup.log}"
if ! touch "$LOG_FILE" 2>/dev/null; then
    echo "[WARN] Cannot write to log file '$LOG_FILE'; falling back to stdout only." >&2
    LOG_FILE="/dev/null"
fi

log() {
    local msg="$1"
    echo "$msg" | tee -a "$LOG_FILE"
}

log "[INFO] Starting full backup: $ARCHIVE_PATH"
TAR_ARGS=()
# Use --warning=no-file-changed to reduce noisy warnings on active filesystems
TAR_ARGS+=(--warning=no-file-changed -C /)
# Add paths to backup (handles both array and string formats)
if [[ -v BACKUP_SRC[@] ]]; then
    # BACKUP_SRC is an array
    for src in "${BACKUP_SRC[@]}"; do
        TAR_ARGS+=("${src#/}")
    done
else
    # BACKUP_SRC is a string (for backward compatibility)
    for src in $BACKUP_SRC; do
        TAR_ARGS+=("${src#/}")
    done
fi

# Create tarstream then compress
log "[INFO] Creating tar archive..."
# Use a temporary file for snapshot instead of /dev/null to avoid permission issues
TEMP_SNAPSHOT=$(mktemp)
TEMP_TAR=$(mktemp --suffix=.tar)
# Create tar (ignore errors from permission denied - some files are created anyway)
tar --listed-incremental="$TEMP_SNAPSHOT" "${TAR_ARGS[@]}" --create --file "$TEMP_TAR" 2>>"$LOG_FILE" || true
# Then compress (this shouldn't fail)
gzip -c < "$TEMP_TAR" > "$ARCHIVE_PATH"
rm -f "$TEMP_SNAPSHOT" "$TEMP_TAR"

log "[INFO] Full backup created: $ARCHIVE_PATH"

# Optionally encrypt
if [[ "${ENCRYPTION:-false}" == "true" ]]; then
    if command -v gpg >/dev/null 2>&1; then
        ENC_PATH="$ARCHIVE_PATH.gpg"
        gpg --batch --yes --output "$ENC_PATH" --encrypt --recipient "${GPG_RECIPIENT}" "$ARCHIVE_PATH"
        if [[ $? -eq 0 ]]; then
            rm -f "$ARCHIVE_PATH"
            log "[INFO] Encrypted archive produced: $ENC_PATH"
        else
            log "[WARN] GPG encryption failed"
        fi
    else
        log "[WARN] gpg not found — skipping encryption"
    fi
fi

# Retention: delete old files
if [[ -n "${RETENTION_DAYS:-}" ]]; then
    log "[INFO] Removing backups older than ${RETENTION_DAYS} days"
    find "$DEST" -maxdepth 1 -type f -mtime +${RETENTION_DAYS} -print -delete >>"$LOG_FILE" 2>&1 || true
fi

log "[INFO] Full backup finished."
