#!/usr/bin/env bash
# Incremental backup script using tar with --listed-incremental (snapshot file)
# Usage: ./incremental_backup.sh [snapshot-file] [destination-dir]
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/config/backup.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

SNAPSHOT="${1:-${SNAPSHOT_FILE:-$BACKUP_DEST/tar.snar}}"
DEST="${2:-${BACKUP_DEST:-/var/backups/sofe3200_backups}}"
mkdir -p "$(dirname "$SNAPSHOT")"
mkdir -p "$DEST"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ARCHIVE_NAME="incr_backup_${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="$DEST/$ARCHIVE_NAME"
LOG_FILE="${LOG_FILE:-$DEST/backup.log}"

echo "[INFO] Starting incremental backup -> $ARCHIVE_PATH (snapshot: $SNAPSHOT)" | tee -a "$LOG_FILE"

# Build tar arguments (handles both array and string formats)
TAR_ARGS=()
TAR_ARGS+=(--warning=no-file-changed -C /)
if [[ -v BACKUP_SRC[@] ]]; then
    # BACKUP_SRC is an array
    for src in "${BACKUP_SRC[@]}"; do
        TAR_ARGS+=("${src#/}")
    done
else
    # BACKUP_SRC is a string (for backward compatibility)
    for src in ${BACKUP_SRC:-/home}; do
        TAR_ARGS+=("${src#/}")
    done
fi

# Create incremental tar (creates or updates the snapshot file)
tar --listed-incremental="$SNAPSHOT" --create --gzip --file="$ARCHIVE_PATH" "${TAR_ARGS[@]}" 2>>"$LOG_FILE"

echo "[INFO] Incremental backup created: $ARCHIVE_PATH" | tee -a "$LOG_FILE"

# Retention
if [[ -n "${RETENTION_DAYS:-}" ]]; then
    echo "[INFO] Removing backups older than ${RETENTION_DAYS} days" | tee -a "$LOG_FILE"
    find "$DEST" -maxdepth 1 -type f -name "incr_backup_*.tar.*" -mtime +${RETENTION_DAYS} -print -delete >>"$LOG_FILE" 2>&1 || true
fi

echo "[INFO] Incremental backup finished." | tee -a "$LOG_FILE"
