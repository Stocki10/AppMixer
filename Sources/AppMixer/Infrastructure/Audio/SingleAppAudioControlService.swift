import Combine
import CoreAudio
import Foundation
import OSLog

@MainActor
final class SingleAppAudioControlService: ObservableObject {
    @Published private(set) var appStates: [String: AppAudioState] = [:]
    @Published private(set) var controlledAppID: String?
    @Published private(set) var isLiveGainAvailable = false

    private let persistence: AppAudioStatePersistence
    private let outputService: CoreAudioOutputService
    private var activeMuteRoute: ActiveMuteRoute?
    private let logger = Logger(subsystem: "AppMixer", category: "SingleAppAudio")

    init(persistence: AppAudioStatePersistence, outputService: CoreAudioOutputService) {
        self.persistence = persistence
        self.outputService = outputService
        self.appStates = persistence.loadAppStates()
    }

    func state(for app: AudioApp) -> AppAudioState {
        appStates[app.id] ?? AppAudioState(appID: app.id, isMuted: false, volume: 1)
    }

    func setMuted(_ muted: Bool, for app: AudioApp) {
        var state = state(for: app)
        state.isMuted = muted
        appStates[app.id] = state

        if muted {
            activateMuteRoute(for: app)
        } else if controlledAppID == app.id {
            deactivateCurrentRoute()
        }
    }

    func setVolume(_ volume: Double, for app: AudioApp) {
        var state = state(for: app)
        state.volume = min(max(volume, 0), 1.5)
        appStates[app.id] = state
        persistence.save(appStates)
    }

    func syncAvailableApps(_ apps: [AudioApp]) {
        let availableIDs = Set(apps.map(\.id))

        if let controlledAppID,
           let activeMuteRoute,
           !availableIDs.contains(controlledAppID) {
            if var state = appStates[controlledAppID], state.isMuted {
                state.isMuted = false
                appStates[controlledAppID] = state
            }

            self.activeMuteRoute = nil
            self.controlledAppID = nil
            destroyMuteRoute(activeMuteRoute)
        }
    }

    private func debugLog(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        NSLog("[SingleAppAudio] %@", message)
    }

    private func activateMuteRoute(for app: AudioApp) {
        if let activeMuteRoute, activeMuteRoute.appID == app.id {
            debugLog("Reusing existing mute route for app=\(app.name) id=\(app.id)")
            controlledAppID = app.id
            return
        }

        deactivateCurrentRoute()

        guard let newRoute = createMuteRoute(for: app) else {
            debugLog("Failed to activate mute route for app=\(app.name) id=\(app.id)")
            var state = state(for: app)
            state.isMuted = false
            appStates[app.id] = state
            return
        }

        debugLog("Activated mute route for app=\(app.name) id=\(app.id)")
        activeMuteRoute = newRoute
        controlledAppID = app.id
    }

    private func deactivateCurrentRoute() {
        guard let activeMuteRoute else {
            controlledAppID = nil
            return
        }

        debugLog("Deactivating mute route for appID=\(activeMuteRoute.appID)")
        self.activeMuteRoute = nil
        controlledAppID = nil
        destroyMuteRoute(activeMuteRoute)
    }

    private func createMuteRoute(for app: AudioApp) -> ActiveMuteRoute? {
        guard #available(macOS 14.2, *) else {
            return nil
        }

        let processIDs = Array(app.processObjectIDs)
        guard !processIDs.isEmpty,
              let outputDeviceUID = outputService.currentOutputDeviceUID() else {
            debugLog("Mute route missing process IDs or output device for app=\(app.name) id=\(app.id)")
            return nil
        }

        let streamIndices = outputService.currentOutputStreamIndices()
        debugLog(
            "Attempting mute route for app=\(app.name) id=\(app.id) processObjectIDs=\(processIDs.map(String.init).joined(separator: ",")) outputDeviceUID=\(outputDeviceUID) streams=\(streamIndices.map(String.init).joined(separator: ","))"
        )

        let tapUUID = UUID()
        let description = CATapDescription(
            __processes: processIDs.map { NSNumber(value: $0) },
            andDeviceUID: outputDeviceUID,
            withStream: streamIndices.first ?? 0
        )
        description.name = "AppMixer Mute \(app.name)"
        description.uuid = tapUUID
        description.isPrivate = true
        description.muteBehavior = CATapMuteBehavior(rawValue: 1)!

        var tapID = AudioObjectID(0)
        let tapStatus = AudioHardwareCreateProcessTap(description, &tapID)
        guard tapStatus == noErr, tapID != 0 else {
            debugLog("Mute route tap creation failed status=\(tapStatus)")
            return nil
        }

        let aggregateUID = "com.appmixer.mute.\(tapUUID.uuidString.lowercased())"
        let tapList: [[String: Any]] = [[
            kAudioSubTapUIDKey: tapUUID.uuidString,
            kAudioSubTapDriftCompensationKey: 1,
            kAudioSubTapDriftCompensationQualityKey: kAudioAggregateDriftCompensationMediumQuality
        ]]
        let subDeviceList: [[String: Any]] = [[
            kAudioSubDeviceUIDKey: outputDeviceUID
        ]]
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceNameKey: "AppMixer Mute \(app.name)",
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: subDeviceList,
            kAudioAggregateDeviceTapListKey: tapList
        ]

        var aggregateDeviceID = AudioObjectID(0)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateDeviceID)
        guard aggregateStatus == noErr, aggregateDeviceID != 0 else {
            debugLog("Mute route aggregate creation failed status=\(aggregateStatus)")
            AudioHardwareDestroyProcessTap(tapID)
            return nil
        }

        var ioProcID: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateDeviceID, nil, makeSilentMuteIOBlock())
        guard ioStatus == noErr, let ioProcID else {
            debugLog("Mute route IOProc creation failed status=\(ioStatus)")
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            AudioHardwareDestroyProcessTap(tapID)
            return nil
        }

        let startStatus = AudioDeviceStart(aggregateDeviceID, ioProcID)
        guard startStatus == noErr else {
            debugLog("Mute route start failed status=\(startStatus)")
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            AudioHardwareDestroyProcessTap(tapID)
            return nil
        }

        debugLog("Mute route created tapID=\(tapID) aggregateDeviceID=\(aggregateDeviceID)")
        return ActiveMuteRoute(appID: app.id, tapID: tapID, aggregateDeviceID: aggregateDeviceID, ioProcID: ioProcID)
    }

    private func destroyMuteRoute(_ activeMuteRoute: ActiveMuteRoute) {
        guard #available(macOS 14.2, *) else {
            return
        }

        AudioDeviceStop(activeMuteRoute.aggregateDeviceID, activeMuteRoute.ioProcID)
        AudioDeviceDestroyIOProcID(activeMuteRoute.aggregateDeviceID, activeMuteRoute.ioProcID)
        AudioHardwareDestroyAggregateDevice(activeMuteRoute.aggregateDeviceID)
        AudioHardwareDestroyProcessTap(activeMuteRoute.tapID)
    }
}

private struct ActiveMuteRoute {
    let appID: String
    let tapID: AudioObjectID
    let aggregateDeviceID: AudioObjectID
    let ioProcID: AudioDeviceIOProcID
}

private func makeSilentMuteIOBlock() -> AudioDeviceIOBlock {
    { _, _, _, outOutputData, _ in
        let outputBuffers = UnsafeMutableAudioBufferListPointer(outOutputData)
        for buffer in outputBuffers {
            if let data = buffer.mData {
                memset(data, 0, Int(buffer.mDataByteSize))
            }
        }
    }
}
