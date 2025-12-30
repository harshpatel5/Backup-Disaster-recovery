#!/usr/bin/env bash
# Verify integrity of backup archive(s).
# Usage: ./verify.sh <archive1> [archive2 ...]
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <archive1> [archive2 ...]"
    exit 2
fi

for archive in "$@"; do
    echo "[INFO] Verifying: $archive"
    if [[ ! -f "$archive" ]]; then
        echo "[ERROR] File not found: $archive"
        continue
    fi

    # If gpg encrypted, try to list after decryption to temporary file
    if [[ "$archive" == *.gpg ]]; then
        if ! command -v gpg >/dev/null 2>&1; then
            echo "[WARN] gpg not installed — cannot verify encrypted archive: $archive"
            continue
        fi
        TMP=$(mktemp --suffix=.tar)
        if ! gpg --batch --yes --output "$TMP" --decrypt "$archive" 2>/dev/null; then
            echo "[ERROR] gpg decryption failed for $archive"
            rm -f "$TMP"
            continue
        fi
        archive="$TMP"
        CLEAN_TMP=true
    else
        CLEAN_TMP=false
    fi

    # Try listing contents
    if tar -tf "$archive" >/dev/null 2>&1; then
        echo "[OK] Archive appears valid: $archive"
    else
        echo "[ERROR] Archive appears corrupted or unreadable: $archive"
    fi

    if [[ "$CLEAN_TMP" == true && -n "${TMP:-}" ]]; then
        rm -f "$TMP"
    fi
done
