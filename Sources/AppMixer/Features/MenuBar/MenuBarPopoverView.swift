import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var systemOutputViewModel: SystemOutputViewModel
    @ObservedObject var appListViewModel: AppListViewModel
    @ObservedObject var outputDevicesViewModel: OutputDevicesViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                OutputSectionView(viewModel: systemOutputViewModel)
                AppsSectionView(viewModel: appListViewModel)
                DeviceSectionView(viewModel: outputDevicesViewModel)
                FooterSectionView(settingsViewModel: settingsViewModel)
            }
            .padding(16)
        }
        .frame(width: 372, height: 520)
    }
}
