import Combine
import Foundation

@MainActor
final class SystemOutputViewModel: ObservableObject {
    @Published private(set) var volume: Double

    @Published private(set) var deviceName: String
    @Published private(set) var isMuted: Bool
    @Published private(set) var mode: ControlMode
    @Published private(set) var canMute: Bool

    private let service: CoreAudioOutputService
    private var cancellables = Set<AnyCancellable>()

    init(service: CoreAudioOutputService) {
        self.service = service
        self.volume = service.state.volume
        self.deviceName = service.state.deviceName
        self.isMuted = service.state.isMuted
        self.mode = service.state.mode
        self.canMute = service.state.canMute

        service.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                if self.volume != state.volume {
                    self.volume = state.volume
                }
                self.deviceName = state.deviceName
                self.isMuted = state.isMuted
                self.mode = state.mode
                self.canMute = state.canMute
            }
            .store(in: &cancellables)
    }

    var modeDescription: String {
        switch mode {
        case .systemOutput:
            return "Controlling Mac output volume"
        case .mixerFallback:
            return "Using AppMixer master volume"
        }
    }

    var volumePercentage: String {
        "\(Int((volume * 100).rounded()))%"
    }

    func setVolume(_ volume: Double) {
        let clamped = min(max(volume, 0), 1)
        guard self.volume != clamped else {
            return
        }

        self.volume = clamped
        service.setVolume(clamped)
    }

    func toggleMute() {
        let newValue = !isMuted
        service.setMuted(newValue)
    }
}
