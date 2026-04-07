import SwiftUI

@main
struct AppMixerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(viewModel: appDelegate.container.settingsViewModel)
                .frame(minWidth: 420, minHeight: 260)
        }
    }
}
