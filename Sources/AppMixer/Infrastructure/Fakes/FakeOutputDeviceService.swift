import Combine
import CoreAudio
import Foundation

@MainActor
final class FakeOutputDeviceService: ObservableObject {
    let devices: [OutputDevice]
    @Published private(set) var currentDeviceID: AudioDeviceID

    private let systemOutputService: FakeSystemOutputService

    init(systemOutputService: FakeSystemOutputService) {
        self.systemOutputService = systemOutputService

        let builtIn = OutputDevice(id: AudioDeviceID(1), name: "MacBook Pro Speakers", supportsSystemVolume: true, supportsSystemMute: true)
        let bluetooth = OutputDevice(id: AudioDeviceID(2), name: "Studio Headphones", supportsSystemVolume: false, supportsSystemMute: false)
        self.devices = [builtIn, bluetooth]
        self.currentDeviceID = builtIn.id
        self.systemOutputService.selectDevice(builtIn)
    }

    func selectDevice(id: AudioDeviceID) {
        currentDeviceID = id

        if let device = devices.first(where: { $0.id == id }) {
            systemOutputService.selectDevice(device)
        }
    }
}
