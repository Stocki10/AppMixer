import Foundation

@MainActor
final class DependencyContainer {
    let systemOutputViewModel: SystemOutputViewModel
    let appListViewModel: AppListViewModel
    let outputDevicesViewModel: OutputDevicesViewModel
    let settingsViewModel: SettingsViewModel

    init() {
        let systemOutputService = CoreAudioOutputService()
        let appDiscoveryService = CoreAudioAppDiscoveryService()
        let appAudioStatePersistence = AppAudioStatePersistence()
        let audioControlService = SingleAppAudioControlService(
            persistence: appAudioStatePersistence,
            outputService: systemOutputService
        )

        self.systemOutputViewModel = SystemOutputViewModel(service: systemOutputService)
        self.appListViewModel = AppListViewModel(service: appDiscoveryService, audioControlService: audioControlService)
        self.outputDevicesViewModel = OutputDevicesViewModel(service: systemOutputService)
        self.settingsViewModel = SettingsViewModel()
    }
}
