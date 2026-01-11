# OmniWM

A powerful tiling window manager for macOS.

![macOS](https://img.shields.io/badge/macOS-26.0%2B-green?logo=apple&logoColor=white)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-supported-green?logo=apple&logoColor=white)
![Intel](https://img.shields.io/badge/X86/X64-supported-green?logo=intel&logoColor=white)
![Claude Code](https://img.shields.io/badge/Claude%20Code-Assisted-green?logo=claude&logoColor=white)

![Image](https://github.com/BarutSRB/OmniWM/blob/f64cedf72a55c14758f5f18fed4ffae75f1b3bed/assets/tabs.gif)]
![Image](https://github.com/BarutSRB/OmniWM/blob/f64cedf72a55c14758f5f18fed4ffae75f1b3bed/assets/animation.gif)

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


