import CoreAudio
import AppKit
import Foundation

struct AudioApp: Identifiable, Hashable {
    let id: String
    let bundleID: String?
    let name: String
    let icon: NSImage?
    let pids: Set<Int32>
    let processObjectIDs: Set<AudioObjectID>
    let isActiveAudio: Bool
    let lastSeenAt: Date
    let isMuted: Bool
    let volume: Double
    let canAdjustVolume: Bool

    init(
        id: String,
        bundleID: String?,
        name: String,
        icon: NSImage?,
        pids: Set<Int32>,
        processObjectIDs: Set<AudioObjectID>,
        isActiveAudio: Bool,
        lastSeenAt: Date,
        isMuted: Bool,
        volume: Double,
        canAdjustVolume: Bool = true
    ) {
        self.id = id
        self.bundleID = bundleID
        self.name = name
        self.icon = icon
        self.pids = pids
        self.processObjectIDs = processObjectIDs
        self.isActiveAudio = isActiveAudio
        self.lastSeenAt = lastSeenAt
        self.isMuted = isMuted
        self.volume = volume
        self.canAdjustVolume = canAdjustVolume
    }
}
