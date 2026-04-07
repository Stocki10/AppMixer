import AppKit
import Combine
import CoreAudio
import Foundation

@MainActor
final class CoreAudioAppDiscoveryService: ObservableObject {
    @Published private(set) var apps: [AudioApp] = []

    private let listenerQueue = DispatchQueue(label: "AppMixer.CoreAudioAppDiscoveryService")
    private lazy var processListListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        Task { @MainActor in
            self?.refresh()
        }
    }
    private lazy var serviceRestartListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        Task { @MainActor in
            self?.refresh()
        }
    }

    private var refreshCancellable: AnyCancellable?
    private var trackedApps: [String: TrackedAudioApp] = [:]
    private let lingerInterval: TimeInterval = 5

    init() {
        installListeners()
        startPolling()
        refresh()
    }

    private func installListeners() {
        var processListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &processListAddress,
            listenerQueue,
            processListListener
        )

        var serviceRestartAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyServiceRestarted,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &serviceRestartAddress,
            listenerQueue,
            serviceRestartListener
        )
    }

    private func startPolling() {
        refreshCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    private func refresh() {
        let now = Date()
        let activeGroups = readActiveGroups(now: now)

        for (groupID, group) in activeGroups {
            trackedApps[groupID] = TrackedAudioApp(
                app: AudioApp(
                    id: group.id,
                    bundleID: group.bundleID,
                    name: group.name,
                    icon: group.icon,
                    pids: group.pids,
                    processObjectIDs: group.processObjectIDs,
                    isActiveAudio: true,
                    lastSeenAt: now,
                    isMuted: false,
                    volume: 1
                ),
                lastSeenAt: now
            )
        }

        trackedApps = trackedApps.reduce(into: [:]) { partialResult, item in
            let groupID = item.key
            let tracked = item.value

            if activeGroups[groupID] != nil {
                partialResult[groupID] = tracked
                return
            }

            guard now.timeIntervalSince(tracked.lastSeenAt) < lingerInterval else {
                return
            }

            partialResult[groupID] = TrackedAudioApp(
                app: AudioApp(
                    id: tracked.app.id,
                    bundleID: tracked.app.bundleID,
                    name: tracked.app.name,
                    icon: tracked.app.icon,
                    pids: tracked.app.pids,
                    processObjectIDs: tracked.app.processObjectIDs,
                    isActiveAudio: false,
                    lastSeenAt: tracked.lastSeenAt,
                    isMuted: tracked.app.isMuted,
                    volume: tracked.app.volume
                ),
                lastSeenAt: tracked.lastSeenAt
            )
        }

        apps = trackedApps.values
            .map(\.app)
            .sorted(by: sortApps)
    }

    private func readActiveGroups(now: Date) -> [String: GroupedProcess] {
        let processObjects = readProcessObjects()
        var grouped: [String: GroupedProcess] = [:]

        for processObject in processObjects {
            guard let pid = readPID(processObject: processObject),
                  pid != getpid(),
                  readIsRunningOutput(processObject: processObject) == true,
                  let candidate = buildCandidate(processObject: processObject, pid: pid)
            else {
                continue
            }

            let grouping = normalizeGroup(for: candidate)

            if var existing = grouped[grouping.id] {
                existing.pids.formUnion([pid])
                existing.processObjectIDs.formUnion([processObject])
                existing.lastSeenAt = now
                if existing.icon == nil {
                    existing.icon = candidate.icon
                }
                grouped[grouping.id] = existing
            } else {
                grouped[grouping.id] = GroupedProcess(
                    id: grouping.id,
                    bundleID: grouping.bundleID,
                    name: grouping.name,
                    icon: candidate.icon,
                    pids: [pid],
                    processObjectIDs: [processObject],
                    lastSeenAt: now
                )
            }
        }

        return grouped
    }

    private func buildCandidate(processObject: AudioObjectID, pid: pid_t) -> ProcessCandidate? {
        guard let runningApplication = NSRunningApplication(processIdentifier: pid) else {
            let bundleID = readBundleID(processObject: processObject)
            return ProcessCandidate(
                pid: pid,
                bundleID: bundleID,
                name: defaultName(bundleID: bundleID, pid: pid),
                icon: nil,
                bundleURL: nil
            )
        }

        let bundleID = runningApplication.bundleIdentifier ?? readBundleID(processObject: processObject)
        let bundleURL = runningApplication.bundleURL
        let name = runningApplication.localizedName
            ?? bundleURL?.deletingPathExtension().lastPathComponent
            ?? defaultName(bundleID: bundleID, pid: pid)

        return ProcessCandidate(
            pid: pid,
            bundleID: bundleID,
            name: name,
            icon: runningApplication.icon,
            bundleURL: bundleURL
        )
    }

    private func normalizeGroup(for candidate: ProcessCandidate) -> GroupIdentity {
        let normalizedBundleID = normalizeHelperBundleID(candidate.bundleID)
        let normalizedName = normalizeHelperName(candidate.name)

        if let normalizedBundleID {
            return GroupIdentity(
                id: normalizedBundleID,
                bundleID: normalizedBundleID,
                name: normalizedName
            )
        }

        return GroupIdentity(
            id: "process-group:\(normalizedName.lowercased().replacingOccurrences(of: " ", with: "-"))",
            bundleID: nil,
            name: normalizedName
        )
    }

    private func normalizeHelperBundleID(_ bundleID: String?) -> String? {
        guard let bundleID else {
            return nil
        }

        let suffixes = [
            ".helper.renderer",
            ".helper.gpu",
            ".helper.plugin",
            ".helper",
            ".renderer",
            ".gpu",
            ".plugin"
        ]

        for suffix in suffixes where bundleID.lowercased().hasSuffix(suffix) {
            return String(bundleID.dropLast(suffix.count))
        }

        return bundleID
    }

    private func normalizeHelperName(_ name: String) -> String {
        var normalized = name

        let patterns = [
            #" Helper( \\(.+\\))?$"#,
            #" Renderer$"#,
            #" GPU$"#,
            #" Plugin$"#,
            #" Web Content$"#
        ]

        for pattern in patterns {
            normalized = normalized.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? name : normalized
    }

    private func defaultName(bundleID: String?, pid: pid_t) -> String {
        bundleID ?? "Process \(pid)"
    }

    private func sortApps(lhs: AudioApp, rhs: AudioApp) -> Bool {
        if lhs.isActiveAudio != rhs.isActiveAudio {
            return lhs.isActiveAudio && !rhs.isActiveAudio
        }

        if lhs.lastSeenAt != rhs.lastSeenAt {
            return lhs.lastSeenAt > rhs.lastSeenAt
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func readProcessObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var processObjects = Array(repeating: AudioObjectID(0), count: count)

        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &processObjects) == noErr else {
            return []
        }

        return processObjects
    }

    private func readPID(processObject: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = 0
        var dataSize = UInt32(MemoryLayout<pid_t>.size)

        let status = AudioObjectGetPropertyData(processObject, &address, 0, nil, &dataSize, &pid)
        guard status == noErr, pid > 0 else {
            return nil
        }

        return pid
    }

    private func readBundleID(processObject: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var bundleID: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = withUnsafeMutablePointer(to: &bundleID) { pointer in
            AudioObjectGetPropertyData(processObject, &address, 0, nil, &dataSize, pointer)
        }

        guard status == noErr, let bundleID else {
            return nil
        }

        return bundleID as String
    }

    private func readIsRunningOutput(processObject: AudioObjectID) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isRunning: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(processObject, &address, 0, nil, &dataSize, &isRunning)
        guard status == noErr else {
            return nil
        }

        return isRunning != 0
    }
}

private struct ProcessCandidate {
    let pid: pid_t
    let bundleID: String?
    let name: String
    let icon: NSImage?
    let bundleURL: URL?
}

private struct GroupIdentity {
    let id: String
    let bundleID: String?
    let name: String
}

private struct GroupedProcess {
    let id: String
    let bundleID: String?
    let name: String
    var icon: NSImage?
    var pids: Set<pid_t>
    var processObjectIDs: Set<AudioObjectID>
    var lastSeenAt: Date
}

private struct TrackedAudioApp {
    let app: AudioApp
    let lastSeenAt: Date
}
