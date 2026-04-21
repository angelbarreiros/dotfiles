#!/bin/bash

# Deploy dotfiles from this repo to the home directory
# This script replaces existing config files with the ones from the repo

set -e

CONFIG_DIR="./.config"
DEST_CONFIG_DIR="$HOME/.config"

echo "🔄 Deploying dotfiles from $(pwd)..."

# Function to backup and copy a file
backup_and_copy() {
    local src="$1"
    local dest="$2"
    
    if [ -f "$dest" ]; then
        local backup="${dest}.backup.$(date +%s)"
        echo "  📦 Backing up: $dest → $backup"
        cp "$dest" "$backup"
    fi
    
    echo "  ✓ Installing: $dest"
    cp "$src" "$dest"
}

# Function to backup and copy a directory
backup_and_copy_dir() {
    local src="$1"
    local dest="$2"
    
    if [ -d "$dest" ]; then
        local backup="${dest}.backup.$(date +%s)"
        echo "  📦 Backing up: $dest → $backup"
        cp -r "$dest" "$backup"
    fi
    
    echo "  ✓ Installing: $dest"
    mkdir -p "$(dirname "$dest")"
    cp -r "$src" "$dest"
}

# Copy Hyprland config
if [ -f "$CONFIG_DIR/hypr/input.conf" ]; then
    echo ""
    echo "📋 Hyprland Configuration:"
    mkdir -p $DEST_CONFIG_DIR/hypr
    backup_and_copy "$CONFIG_DIR/hypr/input.conf" $DEST_CONFIG_DIR/hypr/input.conf
fi

# Copy Git config
if [ -f "$CONFIG_DIR/git/config" ]; then
    echo ""
    echo "🔧 Git Configuration:"
    mkdir -p $DEST_CONFIG_DIR/git
    backup_and_copy "$CONFIG_DIR/git/config" $DEST_CONFIG_DIR/git/config
fi

echo ""
echo "✅ Dotfiles deployed successfully!"
echo "📝 Backups created with .backup.TIMESTAMP suffix if files were replaced"
