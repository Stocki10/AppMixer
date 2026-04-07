import AppKit
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var launchAtLogin: Bool = false

    var permissionsSummary: String {
        "Milestone 1 uses fake data. Permission handling will be added when the Core Audio layers are implemented."
    }

    var footerStatus: String {
        launchAtLogin ? "Launch at Login On" : "Prototype"
    }

    func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func resetState() {
        launchAtLogin = false
    }
}
