# Dotfiles

Personal dotfiles repository for Linux desktop configuration, managed through the Omarchy desktop environment framework.

## Overview

This repository contains configuration files for:
- **Hyprland** - A dynamic tiling Wayland compositor
- **Waybar** - Customizable taskbar/status bar
- **Terminal emulators** - Alacritty, Kitty, Ghostty
- **Application bindings** - Keyboard shortcuts and application launchers
- **Webapp launchers** - Desktop entries for app-mode webapps
- **System configuration** - Window rules, animations, display settings, and themes

## Usage

### Deploy Configuration

To deploy these dotfiles to your system:

```bash
./replace.sh
```

This script will:
- Backup your existing `~/.config/` files to `~/.dotfiles-backups/[timestamp]/`
- Copy configuration files from this repository to your `~/.config/`
- Backup and copy selected `~/.local/share/applications/*.desktop` webapp launchers
- Create timestamped backups for safe restoration

### Restore Configuration

To restore from a previous backup:

```bash
./restore.sh
```

This script will:
- Display all available backup points
- Allow you to select which backup to restore
- Restore files from the selected backup timestamp

## Project Structure

```
.config/
  ├── hypr/          # Hyprland window manager configuration
  ├── waybar/        # Status bar configuration
  ├── alacritty/     # Alacritty terminal configuration
  ├── tmux/          # Tmux terminal multiplexer configuration
  ├── kitty/         # Kitty terminal configuration
  └── ...            # Other configuration directories

replace.sh           # Deploy script - copies dotfiles to ~/.config/ and selected webapp desktop files
restore.sh           # Restore script - recovers from timestamped backups
```

## Important Notes

- **Backup Directory**: Backups are stored in `~/.dotfiles-backups/`
- **System-Managed Files**: This repository does NOT manage `~/.local/share/omarchy/`, which is system-managed and must remain read-only
- **Managed Paths**: These scripts manage `~/.config/` and selected `~/.local/share/applications/*.desktop` launchers

## Requirements

- Linux system with Wayland support
- Omarchy desktop environment framework
- Hyprland window manager
- Bash shell

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
