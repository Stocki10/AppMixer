import AppKit
import Foundation

@MainActor
final class FakeAppDiscoveryService {
    let apps: [AudioApp]

    init() {
        self.apps = [
            AudioApp(
                id: "com.apple.Music",
                bundleID: "com.apple.Music",
                name: "Music",
                icon: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music").flatMap { NSWorkspace.shared.icon(forFile: $0.path) },
                pids: [1204],
                processObjectIDs: [1001],
                isActiveAudio: true,
                lastSeenAt: .now,
                isMuted: false,
                volume: 0.72
            ),
            AudioApp(
                id: "com.google.Chrome",
                bundleID: "com.google.Chrome",
                name: "Chrome",
                icon: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome").flatMap { NSWorkspace.shared.icon(forFile: $0.path) },
                pids: [2290, 2294],
                processObjectIDs: [1002, 1003],
                isActiveAudio: true,
                lastSeenAt: .now.addingTimeInterval(-4),
                isMuted: false,
                volume: 0.58
            ),
            AudioApp(
                id: "us.zoom.xos",
                bundleID: "us.zoom.xos",
                name: "Zoom",
                icon: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "us.zoom.xos").flatMap { NSWorkspace.shared.icon(forFile: $0.path) },
                pids: [3102],
                processObjectIDs: [1004],
                isActiveAudio: true,
                lastSeenAt: .now.addingTimeInterval(-8),
                isMuted: true,
                volume: 0.40
            )
        ]
    }
}
