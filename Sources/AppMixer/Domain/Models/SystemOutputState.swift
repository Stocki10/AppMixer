import CoreAudio
import Foundation

struct SystemOutputState {
    var deviceID: AudioDeviceID?
    var deviceName: String
    var volume: Double
    var isMuted: Bool
    var mode: ControlMode
    var canMute: Bool
}

enum ControlMode {
    case systemOutput
    case mixerFallback
}
