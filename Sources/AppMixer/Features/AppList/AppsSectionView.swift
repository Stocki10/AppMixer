import SwiftUI

struct AppsSectionView: View {
    @ObservedObject var viewModel: AppListViewModel

    var body: some View {
        SectionCard(title: "Apps") {
            if viewModel.apps.isEmpty {
                ContentUnavailableView("No Active Audio Apps", systemImage: "app.badge.fill")
                    .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.apps) { app in
                        AppRowView(
                            app: app,
                            onMuteToggle: { viewModel.setMuted($0, for: app) },
                            onVolumeChange: { viewModel.setVolume($0, for: app) }
                        )
                    }
                }
            }
        }
    }
}
