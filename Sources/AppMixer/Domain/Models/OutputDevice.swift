import CoreAudio
import Foundation

struct OutputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let supportsSystemVolume: Bool
    let supportsSystemMute: Bool
}
