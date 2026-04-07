import Combine
import CoreAudio
import Foundation

@MainActor
final class FakeSystemOutputService: ObservableObject {
    @Published private(set) var state: SystemOutputState

    init() {
        self.state = SystemOutputState(
            deviceID: AudioDeviceID(1),
            deviceName: "MacBook Pro Speakers",
            volume: 0.68,
            isMuted: false,
            mode: .systemOutput,
            canMute: true
        )
    }

    func setVolume(_ volume: Double) {
        state.volume = volume
    }

    func setMuted(_ muted: Bool) {
        state.isMuted = muted
    }

    func selectDevice(_ device: OutputDevice) {
        state.deviceID = device.id
        state.deviceName = device.name
        state.mode = device.supportsSystemVolume ? .systemOutput : .mixerFallback
        state.canMute = device.supportsSystemVolume ? device.supportsSystemMute : true
    }
}
