#!/bin/bash

# Deploy tracked dotfiles from this repository into $HOME.
# This script only manages tracked files and untracked, non-ignored files under:
#   - .config/
#   - .local/share/applications/*.desktop
#   - .local/share/applications/icons/*
# It also installs the pinned Trezor Suite AppImage under ~/Apps.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backups"
TIMESTAMP="$(date +%s)"
BACKUP_ROOT="$BACKUP_DIR/$TIMESTAMP"
TREZOR_SUITE_VERSION="26.6.1"
TREZOR_SUITE_REL_PATH="Apps/Trezor-Suite.AppImage"
TREZOR_SUITE_URL="https://data.trezor.io/suite/releases/desktop/v${TREZOR_SUITE_VERSION}/Trezor-Suite-${TREZOR_SUITE_VERSION}-linux-x86_64.AppImage"
TREZOR_SUITE_SHA512="24d70f493f873fadefe057314b43485a143916c5cc5317ad7798382a91f28a94d4054c2d2dd34883b2bab79188fb0d97740184912bc21a6c0bd2027efc331044"
TREZOR_SUITE_INSTALLED=0
REMOVED_MANAGED_FILES=(
    ".config/hypr/scripts/firefoxpwa-get-ulid.sh"
    ".local/share/applications/Drive.desktop"
    ".local/share/applications/icons/Drive.png"
    ".local/share/applications/orca.desktop"
    "Apps/orca-linux.AppImage"
    "Apps/Images/orca-ide.png"
)
REMOVED_MANAGED_PATHS=(
    ".config/tmux"
)

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

backup_and_remove_file() {
    local rel_path="$1"
    local dest="$HOME/$rel_path"
    local backup_file="$BACKUP_ROOT/$rel_path"

    if [[ ! -e "$dest" ]]; then
        return 1
    fi

    if [[ -f "$dest" && ! -f "$backup_file" ]]; then
        mkdir -p "$(dirname "$backup_file")"
        cp "$dest" "$backup_file"
        echo "  backup: $rel_path"
    fi

    rm -f "$dest"
    echo "  remove: $rel_path"
    return 0
}

backup_and_remove_path() {
    local rel_path="$1"
    local dest="$HOME/$rel_path"
    local backup_path="$BACKUP_ROOT/$rel_path"

    if [[ ! -e "$dest" ]]; then
        return 1
    fi

    if [[ ! -e "$backup_path" ]]; then
        mkdir -p "$(dirname "$backup_path")"
        cp -a "$dest" "$backup_path"
        echo "  backup: $rel_path"
    fi

    rm -rf "$dest"
    echo "  remove: $rel_path"
    return 0
}

install_trezor_suite() {
    local dest="$HOME/$TREZOR_SUITE_REL_PATH"
    local backup_file="$BACKUP_ROOT/$TREZOR_SUITE_REL_PATH"
    local current_checksum=""
    local downloaded_checksum
    local temp_file

    if [[ -f "$dest" ]]; then
        current_checksum="$(sha512sum "$dest" | awk '{print $1}')"
    fi

    if [[ "$current_checksum" == "$TREZOR_SUITE_SHA512" ]]; then
        chmod +x "$dest"
        echo "  verified: $TREZOR_SUITE_REL_PATH (Trezor Suite $TREZOR_SUITE_VERSION)"
        return 0
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo "ERROR: curl is required to install Trezor Suite"
        exit 1
    fi

    temp_file="$(mktemp "${TMPDIR:-/tmp}/trezor-suite.XXXXXX")"
    trap 'rm -f "$temp_file"' RETURN

    echo "  download: Trezor Suite $TREZOR_SUITE_VERSION"
    curl --fail --location --silent --show-error \
        --output "$temp_file" \
        "$TREZOR_SUITE_URL"

    downloaded_checksum="$(sha512sum "$temp_file" | awk '{print $1}')"
    if [[ "$downloaded_checksum" != "$TREZOR_SUITE_SHA512" ]]; then
        echo "ERROR: Trezor Suite checksum verification failed"
        exit 1
    fi

    if [[ -f "$dest" && ! -f "$backup_file" ]]; then
        mkdir -p "$(dirname "$backup_file")"
        cp "$dest" "$backup_file"
        echo "  backup: $TREZOR_SUITE_REL_PATH"
    fi

    mkdir -p "$(dirname "$dest")"
    cp "$temp_file" "$dest"
    chmod 755 "$dest"
    rm -f "$temp_file"
    trap - RETURN
    echo "  install: $TREZOR_SUITE_REL_PATH"
    TREZOR_SUITE_INSTALLED=1
}

installed_count=0
waybar_installed=0
while IFS= read -r rel_path; do
    [[ -z "$rel_path" ]] && continue

    case "$rel_path" in
        .config/*|.local/share/applications/*.desktop|.local/share/applications/icons/*)
            if [[ -f "$SCRIPT_DIR/$rel_path" ]]; then
                backup_and_install_file "$rel_path"
                installed_count=$((installed_count + 1))

                if [[ "$rel_path" == .config/waybar/* ]]; then
                    waybar_installed=1
                fi
            fi
            ;;
    esac
done < <(git -C "$SCRIPT_DIR" ls-files --cached --others --exclude-standard)

install_trezor_suite
installed_count=$((installed_count + TREZOR_SUITE_INSTALLED))

removed_count=0
for rel_path in "${REMOVED_MANAGED_FILES[@]}"; do
    if backup_and_remove_file "$rel_path"; then
        removed_count=$((removed_count + 1))
    fi
done

for rel_path in "${REMOVED_MANAGED_PATHS[@]}"; do
    if backup_and_remove_path "$rel_path"; then
        removed_count=$((removed_count + 1))
    fi
done

echo
echo "Done. Installed $installed_count managed file(s)."
echo "Removed $removed_count retired managed file(s)."
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

if ((waybar_installed)) && command -v omarchy >/dev/null 2>&1; then
    echo
    echo "Restarting Waybar..."
    omarchy restart waybar
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    echo
    echo "Updating desktop app database..."
    mkdir -p "$HOME/.local/share/applications"
    update-desktop-database "$HOME/.local/share/applications"
fi

echo
echo "Tip: run ./restore.sh to roll back."
