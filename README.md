# OmniWM

A powerful tiling window manager for macOS.

![macOS](https://img.shields.io/badge/macOS-26.0%2B-blue)

![Image](https://private-user-images.githubusercontent.com/12249659/530459053-4662ddfd-68c8-4c15-8371-adf48da33bb6.gif?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3NjY4NTE4OTEsIm5iZiI6MTc2Njg1MTU5MSwicGF0aCI6Ii8xMjI0OTY1OS81MzA0NTkwNTMtNDY2MmRkZmQtNjhjOC00YzE1LTgzNzEtYWRmNDhkYTMzYmI2LmdpZj9YLUFtei1BbGdvcml0aG09QVdTNC1ITUFDLVNIQTI1NiZYLUFtei1DcmVkZW50aWFsPUFLSUFWQ09EWUxTQTUzUFFLNFpBJTJGMjAyNTEyMjclMkZ1cy1lYXN0LTElMkZzMyUyRmF3czRfcmVxdWVzdCZYLUFtei1EYXRlPTIwMjUxMjI3VDE2MDYzMVomWC1BbXotRXhwaXJlcz0zMDAmWC1BbXotU2lnbmF0dXJlPTg0NzcwNTcwZGZmOTA1NjE3ZmRkMThlYzkyMjMzNzJlOTEwOTYyN2UzY2JmMjc5ODc0NzBkMzNjMTExYTdkMzEmWC1BbXotU2lnbmVkSGVhZGVycz1ob3N0In0.idrOvdVLNswP8nF84ZMU1jif3bJ5UemjqJgTJMUcLos)

## Features

- **Column-based tiling** - Niri-inspired layout engine that automatically arranges windows in columns
- **Multiple workspaces** - Create and manage virtual workspaces with per-monitor assignment
- **40+ keyboard shortcuts** - Navigate, move, and resize windows efficiently (all customizable)
- **App rules** - Configure per-application behavior (floating, workspace assignment, minimum size)
- **Window borders** - Visual indicator for the focused window
- **Fuzzy finder** - Press `Option + Space` to search through all windows and navigate directly to them
- **Window tabs** - Group multiple windows into tabbed containers for better organization
- **Workspace bar** - Menu bar widget with sorted app icons; click any icon to navigate to that window
- **Focus follows mouse** - Optionally focus windows when hovering over them

## Known Limitations

- **Multi-monitor support** - Not fully tested (developer lacks multi-monitor setup)
- **Gestures/Trackpad** - Magic Mouse and trackpad gestures are untested (no hardware available for testing)

## Requirements

- macOS 26.0 (Sequoia) or later
- Accessibility permissions (prompted on first launch)

## Installation

The app is developer signed and notarized by Apple.

### Homebrew

```bash
brew tap BarutSRB/tap
brew install omniwm
```

### GitHub Releases

1. Download the latest `OmniWM.zip` from [Releases](https://github.com/BarutSRB/OmniWM/releases)
2. Extract and move `OmniWM.app` to `/Applications`
3. Launch OmniWM and grant Accessibility permissions when prompted

## Quick Start

1. Launch OmniWM from your Applications folder
2. Grant Accessibility permissions in System Settings > Privacy & Security > Accessibility
3. Windows will automatically tile in columns
4. Use `Option + Arrow keys` to navigate between windows
5. Click the menu bar icon to access Settings


## Configuration

Access settings by clicking the **O** menu bar icon and selecting **Settings** or **App Rules**.

There are huge amount of features and customizations and I'm really bad at doing guides but the GUI settings/customization should be fairly intuitive, some features have never before been available for macOS tiling WMs.
If anyone is good at making video guides DM me on discord or through GitHub discussions I'd appreciate it.

## App Rules

Configure per-application behavior in Settings > App Rules:

- **Always Float** - Force specific apps to always float (e.g., calculators, preferences windows)
- **Assign to Workspace** - Automatically move app windows to a specific workspace
- **Minimum Size** - Prevent the layout engine from sizing windows below a threshold

## Building from Source

Requirements:
- Xcode with Swift 6.2+
- macOS 26.0+

## Support

If you find OmniWM useful, consider supporting development:

- [GitHub Sponsors](https://github.com/sponsors/BarutSRB)
- [PayPal](https://paypal.me/beacon2024)

## Contributing

Issues and pull requests are welcome on [GitHub](https://github.com/BarutSRB/OmniWM).


