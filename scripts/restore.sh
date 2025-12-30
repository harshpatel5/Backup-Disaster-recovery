#!/usr/bin/env bash
# Restore script for tar archives (supports .tar, .tar.gz, .tar.bz2 and optional .gpg encrypted)
# Usage: ./restore.sh <archive> <destination-path>
set -euo pipefail
IFS=$'\n\t'

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <archive> <destination-path>"
    exit 2
fi

ARCHIVE="$1"
DEST="$2"

if [[ ! -f "$ARCHIVE" ]]; then
    echo "Archive not found: $ARCHIVE"
    exit 3
fi

mkdir -p "$DEST"

# If encrypted (.gpg), decrypt to a temp file first
TMP_ARCHIVE=""
if [[ "$ARCHIVE" == *.gpg ]]; then
    if ! command -v gpg >/dev/null 2>&1; then
        echo "gpg required to decrypt the archive but not found"
        exit 4
    fi
    TMP_ARCHIVE=$(mktemp --suffix=.tar)
    gpg --batch --yes --output "$TMP_ARCHIVE" --decrypt "$ARCHIVE" || { echo "gpg decryption failed"; exit 5; }
    ARCHIVE="$TMP_ARCHIVE"
fi

case "$ARCHIVE" in
    *.tar.gz|*.tgz) tar --extract --gzip --file="$ARCHIVE" --directory="$DEST" ;;
    *.tar.bz2) tar --extract --bzip2 --file="$ARCHIVE" --directory="$DEST" ;;
    *.tar) tar --extract --file="$ARCHIVE" --directory="$DEST" ;;
    *) echo "Unknown archive type. Supported: .tar .tar.gz .tar.bz2 .gpg encrypted"; exit 6 ;;
esac

echo "[INFO] Restore complete to $DEST"

# Cleanup tmp
if [[ -n "${TMP_ARCHIVE:-}" && -f "$TMP_ARCHIVE" ]]; then
    rm -f "$TMP_ARCHIVE"
fi
