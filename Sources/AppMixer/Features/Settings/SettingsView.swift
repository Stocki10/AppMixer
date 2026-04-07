import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Toggle("Launch at Login", isOn: $viewModel.launchAtLogin)

            Section("Permissions") {
                Text(viewModel.permissionsSummary)
                    .foregroundStyle(.secondary)
            }

            Section("Data") {
                Button("Reset Sample State") {
                    viewModel.resetState()
                }
            }
        }
        .padding(20)
    }
}
