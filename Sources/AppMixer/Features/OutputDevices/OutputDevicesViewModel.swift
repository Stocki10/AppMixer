import CoreAudio
import Combine
import Foundation

@MainActor
final class OutputDevicesViewModel: ObservableObject {
    @Published private(set) var devices: [OutputDevice]
    @Published private(set) var currentDeviceID: AudioDeviceID?

    private let service: CoreAudioOutputService
    private var cancellables = Set<AnyCancellable>()

    init(service: CoreAudioOutputService) {
        self.service = service
        self.devices = service.devices
        self.currentDeviceID = service.currentDeviceID

        service.$devices
            .receive(on: RunLoop.main)
            .assign(to: &$devices)

        service.$currentDeviceID
            .receive(on: RunLoop.main)
            .assign(to: &$currentDeviceID)
    }

    var currentDeviceName: String {
        guard let currentDeviceID else {
            return "No Output Device"
        }

        return devices.first(where: { $0.id == currentDeviceID })?.name ?? "Unknown Device"
    }

    func selectDevice(id: AudioDeviceID) {
        service.selectDevice(id: id)
    }
}
