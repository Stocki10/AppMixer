import SwiftUI

struct FooterSectionView: View {
    @ObservedObject var settingsViewModel: SettingsViewModel

    var body: some View {
        HStack {
            Button("Settings...") {
                settingsViewModel.openSettings()
            }

            Spacer()

            Text(settingsViewModel.footerStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
