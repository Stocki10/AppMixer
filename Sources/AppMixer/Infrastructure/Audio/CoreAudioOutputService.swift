import Combine
import CoreAudio
import Foundation

@MainActor
final class CoreAudioOutputService: ObservableObject {
    @Published private(set) var state: SystemOutputState
    @Published private(set) var devices: [OutputDevice] = []
    @Published private(set) var currentDeviceID: AudioDeviceID?

    private let listenerQueue = DispatchQueue(label: "AppMixer.CoreAudioOutputService")

    private var observedDeviceID: AudioDeviceID?
    private lazy var defaultDeviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        Task { @MainActor in
            self?.refresh()
        }
    }
    private lazy var deviceListListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        Task { @MainActor in
            self?.refresh()
        }
    }
    private lazy var deviceStateListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        Task { @MainActor in
            self?.refreshCurrentDeviceState()
        }
    }

    private var mixerFallbackVolume: Double = 0.65
    private var mixerFallbackMuted = false

    init() {
        self.state = SystemOutputState(
            deviceID: nil,
            deviceName: "No Output Device",
            volume: 0.65,
            isMuted: false,
            mode: .mixerFallback,
            canMute: true
        )

        installSystemListeners()
        refresh()
    }

    func setVolume(_ volume: Double) {
        let clamped = min(max(volume, 0), 1)

        switch state.mode {
        case .systemOutput:
            guard let deviceID = currentDeviceID else {
                setFallbackVolume(clamped)
                return
            }

            if writeVolume(clamped, deviceID: deviceID) {
                state.volume = clamped
            }

        case .mixerFallback:
            setFallbackVolume(clamped)
        }
    }

    func setMuted(_ muted: Bool) {
        switch state.mode {
        case .systemOutput:
            guard state.canMute, let deviceID = currentDeviceID else {
                return
            }

            if writeMute(muted, deviceID: deviceID) {
                state.isMuted = muted
            }

        case .mixerFallback:
            mixerFallbackMuted = muted
            state.isMuted = muted
        }
    }

    func selectDevice(id: AudioDeviceID) {
        var deviceID = id
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )

        if status == noErr {
            refresh()
        }
    }

    func currentOutputDeviceUID() -> String? {
        guard let deviceID = currentDeviceID else {
            return nil
        }

        return readDeviceUID(deviceID: deviceID)
    }

    func currentOutputStreamIndices() -> [Int] {
        guard let deviceID = currentDeviceID else {
            return []
        }

        let count = readStreams(deviceID: deviceID, scope: kAudioObjectPropertyScopeOutput).count
        return Array(0 ..< count)
    }

    private func refresh() {
        let newDevices = loadOutputDevices()
        devices = newDevices

        let newCurrentDeviceID = readDefaultOutputDeviceID()
        currentDeviceID = newCurrentDeviceID

        updateObservedDevice(oldID: observedDeviceID, newID: newCurrentDeviceID)

        guard let deviceID = newCurrentDeviceID,
              let device = newDevices.first(where: { $0.id == deviceID }) else {
            state = SystemOutputState(
                deviceID: nil,
                deviceName: "No Output Device",
                volume: mixerFallbackVolume,
                isMuted: mixerFallbackMuted,
                mode: .mixerFallback,
                canMute: true
            )
            return
        }

        let useSystemOutput = device.supportsSystemVolume
        let volume = useSystemOutput ? readVolume(deviceID: deviceID) ?? mixerFallbackVolume : mixerFallbackVolume
        let muted = useSystemOutput ? readMute(deviceID: deviceID) ?? false : mixerFallbackMuted

        state = SystemOutputState(
            deviceID: deviceID,
            deviceName: device.name,
            volume: volume,
            isMuted: muted,
            mode: useSystemOutput ? .systemOutput : .mixerFallback,
            canMute: useSystemOutput ? device.supportsSystemMute : true
        )
    }

    private func readStreams(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> [AudioStreamID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioStreamID>.size
        var streams = Array(repeating: AudioStreamID(0), count: count)

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &streams) == noErr else {
            return []
        }

        return streams
    }

    private func refreshCurrentDeviceState() {
        guard let deviceID = currentDeviceID,
              let device = devices.first(where: { $0.id == deviceID }) else {
            refresh()
            return
        }

        if device.supportsSystemVolume {
            state.volume = readVolume(deviceID: deviceID) ?? state.volume
            state.isMuted = readMute(deviceID: deviceID) ?? state.isMuted
            state.canMute = device.supportsSystemMute
            state.mode = .systemOutput
        } else {
            state.volume = mixerFallbackVolume
            state.isMuted = mixerFallbackMuted
            state.canMute = true
            state.mode = .mixerFallback
        }

        state.deviceID = deviceID
        state.deviceName = device.name
    }

    private func setFallbackVolume(_ volume: Double) {
        mixerFallbackVolume = volume
        state.volume = volume
    }

    private func installSystemListeners() {
        var defaultOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddress,
            listenerQueue,
            defaultDeviceListener
        )

        var deviceListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceListAddress,
            listenerQueue,
            deviceListListener
        )
    }

    private func updateObservedDevice(oldID: AudioDeviceID?, newID: AudioDeviceID?) {
        guard oldID != newID else {
            return
        }

        if let oldID {
            removeDeviceListeners(deviceID: oldID)
        }

        observedDeviceID = newID

        if let newID {
            addDeviceListeners(deviceID: newID)
        }
    }

    private func addDeviceListeners(deviceID: AudioDeviceID) {
        for address in devicePropertyAddresses() {
            var mutableAddress = address
            AudioObjectAddPropertyListenerBlock(deviceID, &mutableAddress, listenerQueue, deviceStateListener)
        }
    }

    private func removeDeviceListeners(deviceID: AudioDeviceID) {
        for address in devicePropertyAddresses() {
            var mutableAddress = address
            AudioObjectRemovePropertyListenerBlock(deviceID, &mutableAddress, listenerQueue, deviceStateListener)
        }
    }

    private func devicePropertyAddresses() -> [AudioObjectPropertyAddress] {
        [
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: 1
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: 2
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: 1
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: 2
            )
        ]
    }

    private func loadOutputDevices() -> [OutputDevice] {
        let allDeviceIDs = readAllDeviceIDs()

        return allDeviceIDs.compactMap { deviceID in
            guard hasOutputStreams(deviceID: deviceID) else {
                return nil
            }

            let name = readDeviceName(deviceID: deviceID) ?? "Audio Device \(deviceID)"
            let supportsVolume = hasWritableVolume(deviceID: deviceID)
            let supportsMute = hasWritableMute(deviceID: deviceID)

            return OutputDevice(
                id: deviceID,
                name: name,
                supportsSystemVolume: supportsVolume,
                supportsSystemMute: supportsMute
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func readDefaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr, deviceID != 0 else {
            return nil
        }

        return deviceID
    }

    private func readAllDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: count)

        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return []
        }

        return deviceIDs
    }

    private func readDeviceName(deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = withUnsafeMutablePointer(to: &name) { namePointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, namePointer)
        }

        guard status == noErr, let name else {
            return nil
        }

        return name as String
    }

    private func readDeviceUID(deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = withUnsafeMutablePointer(to: &uid) { uidPointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, uidPointer)
        }

        guard status == noErr, let uid else {
            return nil
        }

        return uid as String
    }

    private func hasOutputStreams(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else {
            return false
        }

        let rawBuffer = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawBuffer.deallocate() }

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, rawBuffer)
        guard status == noErr else {
            return false
        }

        let audioBufferList = rawBuffer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let channelCount = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
        return channelCount > 0
    }

    private func hasWritableVolume(deviceID: AudioDeviceID) -> Bool {
        writableScalarAddress(deviceID: deviceID) != nil
    }

    private func hasWritableMute(deviceID: AudioDeviceID) -> Bool {
        writableMuteAddress(deviceID: deviceID) != nil
    }

    private func readVolume(deviceID: AudioDeviceID) -> Double? {
        if let address = scalarAddressIfPresent(deviceID: deviceID, element: kAudioObjectPropertyElementMain),
           let value = readFloat32(deviceID: deviceID, address: address) {
            return Double(value)
        }

        let channelValues = [UInt32(1), UInt32(2)].compactMap { element in
            scalarAddressIfPresent(deviceID: deviceID, element: element).flatMap { readFloat32(deviceID: deviceID, address: $0) }
        }

        guard !channelValues.isEmpty else {
            return nil
        }

        let average = channelValues.reduce(0, +) / Float(channelValues.count)
        return Double(average)
    }

    private func readMute(deviceID: AudioDeviceID) -> Bool? {
        if let address = muteAddressIfPresent(deviceID: deviceID, element: kAudioObjectPropertyElementMain),
           let value = readUInt32(deviceID: deviceID, address: address) {
            return value != 0
        }

        if let address = muteAddressIfPresent(deviceID: deviceID, element: 1),
           let value = readUInt32(deviceID: deviceID, address: address) {
            return value != 0
        }

        if let address = muteAddressIfPresent(deviceID: deviceID, element: 2),
           let value = readUInt32(deviceID: deviceID, address: address) {
            return value != 0
        }

        return nil
    }

    private func writeVolume(_ volume: Double, deviceID: AudioDeviceID) -> Bool {
        let scalar = Float32(volume)

        if let address = writableScalarAddress(deviceID: deviceID) {
            return writeFloat32(scalar, deviceID: deviceID, address: address)
        }

        let writableChannels = [UInt32(1), UInt32(2)].compactMap { scalarAddressIfSettable(deviceID: deviceID, element: $0) }
        guard !writableChannels.isEmpty else {
            return false
        }

        return writableChannels.reduce(true) { partialResult, address in
            writeFloat32(scalar, deviceID: deviceID, address: address) && partialResult
        }
    }

    private func writeMute(_ muted: Bool, deviceID: AudioDeviceID) -> Bool {
        let scalar: UInt32 = muted ? 1 : 0

        if let address = writableMuteAddress(deviceID: deviceID) {
            return writeUInt32(scalar, deviceID: deviceID, address: address)
        }

        let writableChannels = [UInt32(1), UInt32(2)].compactMap { muteAddressIfSettable(deviceID: deviceID, element: $0) }
        guard !writableChannels.isEmpty else {
            return false
        }

        return writableChannels.reduce(true) { partialResult, address in
            writeUInt32(scalar, deviceID: deviceID, address: address) && partialResult
        }
    }

    private func writableScalarAddress(deviceID: AudioDeviceID) -> AudioObjectPropertyAddress? {
        scalarAddressIfSettable(deviceID: deviceID, element: kAudioObjectPropertyElementMain)
            ?? scalarAddressIfSettable(deviceID: deviceID, element: 1)
            ?? scalarAddressIfSettable(deviceID: deviceID, element: 2)
    }

    private func writableMuteAddress(deviceID: AudioDeviceID) -> AudioObjectPropertyAddress? {
        muteAddressIfSettable(deviceID: deviceID, element: kAudioObjectPropertyElementMain)
            ?? muteAddressIfSettable(deviceID: deviceID, element: 1)
            ?? muteAddressIfSettable(deviceID: deviceID, element: 2)
    }

    private func scalarAddressIfPresent(deviceID: AudioDeviceID, element: UInt32) -> AudioObjectPropertyAddress? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )

        return AudioObjectHasProperty(deviceID, &address) ? address : nil
    }

    private func scalarAddressIfSettable(deviceID: AudioDeviceID, element: UInt32) -> AudioObjectPropertyAddress? {
        let address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )

        return isPropertySettable(deviceID: deviceID, address: address) ? address : nil
    }

    private func muteAddressIfPresent(deviceID: AudioDeviceID, element: UInt32) -> AudioObjectPropertyAddress? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )

        return AudioObjectHasProperty(deviceID, &address) ? address : nil
    }

    private func muteAddressIfSettable(deviceID: AudioDeviceID, element: UInt32) -> AudioObjectPropertyAddress? {
        let address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )

        return isPropertySettable(deviceID: deviceID, address: address) ? address : nil
    }

    private func isPropertySettable(deviceID: AudioDeviceID, address: AudioObjectPropertyAddress) -> Bool {
        var mutable = address
        guard AudioObjectHasProperty(deviceID, &mutable) else {
            return false
        }

        var settable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(deviceID, &mutable, &settable)
        return status == noErr && settable.boolValue
    }

    private func readFloat32(deviceID: AudioDeviceID, address: AudioObjectPropertyAddress) -> Float32? {
        var mutable = address
        var value = Float32(0)
        var dataSize = UInt32(MemoryLayout<Float32>.size)

        let status = AudioObjectGetPropertyData(deviceID, &mutable, 0, nil, &dataSize, &value)
        return status == noErr ? value : nil
    }

    private func readUInt32(deviceID: AudioDeviceID, address: AudioObjectPropertyAddress) -> UInt32? {
        var mutable = address
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(deviceID, &mutable, 0, nil, &dataSize, &value)
        return status == noErr ? value : nil
    }

    private func writeFloat32(_ value: Float32, deviceID: AudioDeviceID, address: AudioObjectPropertyAddress) -> Bool {
        var mutable = address
        var mutableValue = value
        let status = AudioObjectSetPropertyData(deviceID, &mutable, 0, nil, UInt32(MemoryLayout<Float32>.size), &mutableValue)
        return status == noErr
    }

    private func writeUInt32(_ value: UInt32, deviceID: AudioDeviceID, address: AudioObjectPropertyAddress) -> Bool {
        var mutable = address
        var mutableValue = value
        let status = AudioObjectSetPropertyData(deviceID, &mutable, 0, nil, UInt32(MemoryLayout<UInt32>.size), &mutableValue)
        return status == noErr
    }
}
