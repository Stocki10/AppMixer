# AppMixer

AppMixer is a native macOS menu bar app prototype for per-app audio control.

## MVP Scope

- Menu bar app with an icon-only status item
- Native popover UI with `Output`, `Apps`, and `Device` sections
- Top control that will prefer macOS system output volume and fall back to mixer master when needed
- Active audio app discovery and grouping
- Per-app mute and volume controls
- Persistence by normalized app identity
- Launch at login

## Current State

This repository currently implements Milestones 1 through 4 plus the first persistence slice from Milestone 5:

- standalone repo scaffold
- native menu bar shell
- real Core Audio output device enumeration
- default output device tracking
- system volume and mute control where supported
- automatic mixer-master fallback mode for unsupported devices
- Core Audio-backed active audio app discovery for the `Apps` section
- conservative helper-process grouping with a short linger window
- single-app mute and gain control through a private tap route
- persisted per-app volume preferences by normalized app identity
- settings scene
- architecture and milestone docs

## Requirements

- macOS 14.2+
- Swift 6+
- Xcode 16+ recommended

## Run

Open the package in Xcode and run the `AppMixer` executable target, or use:

```bash
swift run
```

## Notes

- This repo is direct-download first, not Mac App Store scoped.
- The `Output`, `Device`, and `Apps` sections are Core Audio-backed.
- App control currently supports one live tapped app route at a time.
- Multi-app control remains in Milestone 5.
