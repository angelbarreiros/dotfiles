#!/bin/bash

# Deploy tracked dotfiles from this repository into $HOME.
# This script only manages tracked files and untracked, non-ignored files under:
#   - .config/
#   - .local/share/applications/*.desktop
#   - .local/share/applications/icons/*

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backups"
TIMESTAMP="$(date +%s)"
BACKUP_ROOT="$BACKUP_DIR/$TIMESTAMP"

if ! command -v git >/dev/null 2>&1; then
    echo "ERROR: git is required to run replace.sh"
    exit 1
fi

if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: $SCRIPT_DIR is not a git repository"
    exit 1
fi

echo "Deploying tracked dotfiles from: $SCRIPT_DIR"
echo "Backup timestamp: $TIMESTAMP ($(date -d "@$TIMESTAMP" '+%Y-%m-%d %H:%M:%S'))"
echo

mkdir -p "$BACKUP_ROOT"

backup_and_install_file() {
    local rel_path="$1"
    local src="$SCRIPT_DIR/$rel_path"
    local dest="$HOME/$rel_path"
    local backup_file="$BACKUP_ROOT/$rel_path"

    if [[ -f "$dest" && ! -f "$backup_file" ]]; then
        mkdir -p "$(dirname "$backup_file")"
        cp "$dest" "$backup_file"
        echo "  backup: $rel_path"
    fi

    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    echo "  install: $rel_path"

    if [[ "$rel_path" == *.sh ]]; then
        chmod +x "$dest"
    fi
}

installed_count=0
while IFS= read -r rel_path; do
    [[ -z "$rel_path" ]] && continue

    case "$rel_path" in
        .config/*|.local/share/applications/*.desktop|.local/share/applications/icons/*)
            if [[ -f "$SCRIPT_DIR/$rel_path" ]]; then
                backup_and_install_file "$rel_path"
                installed_count=$((installed_count + 1))
            fi
            ;;
    esac
done < <(git -C "$SCRIPT_DIR" ls-files --cached --others --exclude-standard)

echo
echo "Done. Installed $installed_count managed file(s)."
if [[ -n "$(find "$BACKUP_ROOT" -type f -print -quit 2>/dev/null)" ]]; then
    echo "Backup saved to: $BACKUP_ROOT"
else
    rmdir "$BACKUP_ROOT" 2>/dev/null || true
    echo "No previous files needed backup."
fi

if command -v hyprctl >/dev/null 2>&1; then
    echo
    echo "Reloading Hyprland..."
    hyprctl reload
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    echo
    echo "Updating desktop app database..."
    mkdir -p "$HOME/.local/share/applications"
    update-desktop-database "$HOME/.local/share/applications"
fi

echo
echo "Tip: run ./restore.sh to roll back."
