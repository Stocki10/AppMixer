# Architecture

## Layers

### App

- SwiftUI app entry point
- App delegate for menu bar lifecycle
- AppKit menu bar controller and popover wiring

### Features

- `SystemOutputViewModel`
- `AppListViewModel`
- `OutputDevicesViewModel`
- `SettingsViewModel`

### Domain

- stable models for apps, devices, and audio state
- narrow service protocols for discovery, output devices, persistence, permissions, and login items

### Infrastructure

- Core Audio-backed output device and system volume service for Milestone 2
- Core Audio-backed app discovery service for Milestone 3
- single-app tap-based mute control service for Milestone 4
- later multi-app audio engine and gain render path implementations

## Popover Structure

1. Output
2. Apps
3. Device
4. Footer actions

## Output Control Rule

The top section uses system output volume and mute when the current output device supports writable controls. If it does not, the same UI binds to the app's mixer-master fallback state.

## Current Implementation Status

- `Output` and `Device` are implemented through `CoreAudioOutputService`
- `Apps` is implemented through `CoreAudioAppDiscoveryService`
- App grouping is conservative and currently normalizes common helper suffixes
- `SingleAppAudioControlService` owns the M4 single-app mute tap path
- Per-app gain now persists by normalized app identity while the full render path remains pending
