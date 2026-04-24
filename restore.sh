#!/bin/bash

# Restore user dotfiles from timestamped backups
# This script restores managed paths from backup (~/.config and selected desktop entries).
# It does NOT modify ~/.local/share/omarchy/
# (which is managed by the system and must remain read-only)

set -e

BACKUP_DIR="$HOME/.dotfiles-backups"

if [ ! -d "$BACKUP_DIR" ]; then
    echo "❌ No backups directory found at $BACKUP_DIR"
    exit 1
fi

echo "🔄 Restore dotfiles from backups..."
echo ""

# Find all backup timestamps (directories in BACKUP_DIR)
backups=($(ls -d "$BACKUP_DIR"/*/ 2>/dev/null | sort -r | xargs -I {} basename {}))

if [ ${#backups[@]} -eq 0 ]; then
    echo "❌ No backups found in $BACKUP_DIR"
    exit 1
fi

echo "📦 Available backup points:"
echo ""

for i in "${!backups[@]}"; do
    timestamp="${backups[$i]}"
    date_str=$(date -d @$timestamp '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown date")
    file_count=$(find "$BACKUP_DIR/$timestamp" -type f | wc -l)
    
    echo "  [$((i+1))] $date_str (timestamp: $timestamp) - $file_count files"
done

echo ""
read -p "Select backup to restore (number): " selection

if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#backups[@]} ]; then
    echo "❌ Invalid selection!"
    exit 1
fi

idx=$((selection - 1))
selected_timestamp="${backups[$idx]}"
selected_backup="$BACKUP_DIR/$selected_timestamp"
date_str=$(date -d @$selected_timestamp '+%Y-%m-%d %H:%M:%S')

echo ""
echo "Restoring backup from: $date_str"
echo "Files to restore:"
find "$selected_backup" -type f | sed 's|'"$selected_backup"'||g' | sed 's|^|  - |'
echo ""

read -p "Are you sure? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Cancelled."
    exit 0
fi

# Create a new backup of current state first
current_timestamp=$(date +%s)
echo ""
echo "  📦 Creating backup of current state: $BACKUP_DIR/$current_timestamp"
mkdir -p "$BACKUP_DIR/$current_timestamp"

# Backup current files
while IFS= read -r backup_file; do
    original_file="${backup_file#$selected_backup}"
    original_full_path="$HOME$original_file"
    
    if [ -f "$original_full_path" ] || [ -d "$original_full_path" ]; then
        current_backup_file="$BACKUP_DIR/$current_timestamp$original_file"
        mkdir -p "$(dirname "$current_backup_file")"
        cp -r "$original_full_path" "$current_backup_file"
    fi
done < <(find "$selected_backup" -type f)

# Restore files from selected backup
echo "  ✓ Restoring files..."
while IFS= read -r backup_file; do
    original_file="${backup_file#$selected_backup}"
    original_full_path="$HOME$original_file"
    
    mkdir -p "$(dirname "$original_full_path")"
    cp "$backup_file" "$original_full_path"
done < <(find "$selected_backup" -type f)

echo ""
echo "✅ Restore completed!"
echo "📝 Current state backed up to: $BACKUP_DIR/$current_timestamp"

# Reload Hyprland config if available
if command -v hyprctl &> /dev/null; then
    echo ""
    echo "🔄 Reloading Hyprland..."
    hyprctl reload
    echo "✓ Hyprland reloaded"
fi
