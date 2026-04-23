#!/bin/bash

# Deploy user dotfiles from this repo to the home directory
# This script only manages ~/.config/ - it does NOT modify ~/.local/share/omarchy/
# (which is managed by the system and must remain read-only)

set -e

CONFIG_DIR="./.config"
DEST_CONFIG_DIR="$HOME/.config"
BACKUP_DIR="$HOME/.dotfiles-backups"
TIMESTAMP=$(date +%s)

echo "🔄 Deploying dotfiles from $(pwd)..."
echo "📦 Backup timestamp: $TIMESTAMP ($(date -d @$TIMESTAMP '+%Y-%m-%d %H:%M:%S'))"
echo ""

mkdir -p "$BACKUP_DIR/$TIMESTAMP"

# Function to backup and copy a file
backup_and_copy() {
    local src="$1"
    local dest="$2"
    
    if [ -f "$dest" ]; then
        local relative_path="${dest#$HOME/}"
        local backup_file="$BACKUP_DIR/$TIMESTAMP/$relative_path"
        mkdir -p "$(dirname "$backup_file")"
        echo "  📦 Backing up: $relative_path"
        cp "$dest" "$backup_file"
    fi
    
    echo "  ✓ Installing: $dest"
    cp "$src" "$dest"
}

# Function to backup and copy a directory
backup_and_copy_dir() {
    local src="$1"
    local dest="$2"
    
    if [ -d "$dest" ]; then
        local relative_path="${dest#$HOME/}"
        local backup_dir="$BACKUP_DIR/$TIMESTAMP/$relative_path"
        mkdir -p "$backup_dir"
        echo "  📦 Backing up: $relative_path"
        cp -r "$dest"/* "$backup_dir/" 2>/dev/null || true
    fi
    
    echo "  ✓ Installing: $dest"
    mkdir -p "$(dirname "$dest")"
    cp -r "$src" "$dest"
}

# Copy Hyprland config
if [ -d "$CONFIG_DIR/hypr" ]; then
    echo ""
    echo "📋 Hyprland Configuration:"
    mkdir -p $DEST_CONFIG_DIR/hypr
    backup_and_copy "$CONFIG_DIR/hypr/env.conf" $DEST_CONFIG_DIR/hypr/env.conf
    backup_and_copy "$CONFIG_DIR/hypr/input.conf" $DEST_CONFIG_DIR/hypr/input.conf
    backup_and_copy "$CONFIG_DIR/hypr/bindings.conf" $DEST_CONFIG_DIR/hypr/bindings.conf
    backup_and_copy "$CONFIG_DIR/hypr/monitors.conf" $DEST_CONFIG_DIR/hypr/monitors.conf
    
fi

# Copy Git config
if [ -f "$CONFIG_DIR/git/config" ]; then
    echo ""
    echo "🔧 Git Configuration:"
    mkdir -p $DEST_CONFIG_DIR/git
    backup_and_copy "$CONFIG_DIR/git/config" $DEST_CONFIG_DIR/git/config
fi

# Copy Alacritty config
if [ -f "$CONFIG_DIR/alacritty/alacritty.toml" ]; then
    echo ""
    echo "🖥️  Alacritty Configuration:"
    mkdir -p $DEST_CONFIG_DIR/alacritty
    backup_and_copy "$CONFIG_DIR/alacritty/alacritty.toml" $DEST_CONFIG_DIR/alacritty/alacritty.toml
fi

# Copy Tmux config
if [ -f "$CONFIG_DIR/tmux/tmux.conf" ]; then
    echo ""
    echo "📋 Tmux Configuration:"
    mkdir -p $DEST_CONFIG_DIR/tmux
    backup_and_copy "$CONFIG_DIR/tmux/tmux.conf" $DEST_CONFIG_DIR/tmux/tmux.conf
fi

# Copy root .tmux.conf
if [ -f ".tmux.conf" ]; then
    echo "  ✓ Installing: ~/.tmux.conf"
    if [ -f "$HOME/.tmux.conf" ]; then
        backup_file="$BACKUP_DIR/$TIMESTAMP/.tmux.conf"
        mkdir -p "$(dirname "$backup_file")"
        echo "  📦 Backing up: .tmux.conf"
        cp "$HOME/.tmux.conf" "$backup_file"
    fi
    cp ".tmux.conf" "$HOME/.tmux.conf"
fi

echo ""
echo "✅ Dotfiles deployed successfully!"
if [ "$(ls -A $BACKUP_DIR/$TIMESTAMP 2>/dev/null)" ]; then
    echo "📦 Backup saved to: $BACKUP_DIR/$TIMESTAMP"
else
    echo "ℹ️  No backups were created (first deployment)"
fi

# Reload Hyprland config if available
if command -v hyprctl &> /dev/null; then
    echo ""
    echo "🔄 Reloading Hyprland..."
    hyprctl reload
    echo "✓ Hyprland reloaded"
fi

# Update desktop app database
if command -v update-desktop-database &> /dev/null; then
    echo ""
    echo "🔄 Updating desktop app database..."
    mkdir -p "$HOME/.local/share/applications"
    update-desktop-database "$HOME/.local/share/applications"
    echo "✓ Desktop apps updated"
fi

echo "💡 Use ./restore.sh to rollback to a previous version"
