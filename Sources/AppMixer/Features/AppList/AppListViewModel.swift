import Combine
import Foundation

@MainActor
final class AppListViewModel: ObservableObject {
    @Published private(set) var apps: [AudioApp]
    @Published private(set) var statusText: String

    private let discoveryService: CoreAudioAppDiscoveryService
    private let audioControlService: SingleAppAudioControlService
    private var cancellables = Set<AnyCancellable>()

    init(service: CoreAudioAppDiscoveryService, audioControlService: SingleAppAudioControlService) {
        self.discoveryService = service
        self.audioControlService = audioControlService
        self.apps = []
        self.statusText = "Single-app mute and gain are live for one app at a time. App slider values still persist by app identity."

        Publishers.CombineLatest4(
            service.$apps,
            audioControlService.$appStates,
            audioControlService.$controlledAppID,
            audioControlService.$isLiveGainAvailable
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] discoveredApps, appStates, controlledAppID, isLiveGainAvailable in
                guard let self else { return }

                self.audioControlService.syncAvailableApps(discoveredApps)
                self.apps = discoveredApps.map { app in
                    let state = appStates[app.id] ?? AppAudioState(appID: app.id, isMuted: false, volume: 1)

                    return AudioApp(
                        id: app.id,
                        bundleID: app.bundleID,
                        name: app.name,
                        icon: app.icon,
                        pids: app.pids,
                        processObjectIDs: app.processObjectIDs,
                        isActiveAudio: app.isActiveAudio,
                        lastSeenAt: app.lastSeenAt,
                        isMuted: state.isMuted,
                        volume: state.volume,
                        canAdjustVolume: false
                    )
                }

                if let controlledAppID,
                   let app = self.apps.first(where: { $0.id == controlledAppID }) {
                    self.statusText = "Single-app control active for \(app.name)"
                } else if !isLiveGainAvailable {
                    self.statusText = "Live app-volume routing is unavailable on the current output device. App mute still works."
                } else {
                    self.statusText = "Single-app mute and gain are live for one app at a time. App slider values still persist by app identity."
                }
            }
            .store(in: &cancellables)
    }

    func setMuted(_ muted: Bool, for app: AudioApp) {
        audioControlService.setMuted(muted, for: app)
    }

    func setVolume(_ volume: Double, for app: AudioApp) {
        audioControlService.setVolume(volume, for: app)
    }
}
