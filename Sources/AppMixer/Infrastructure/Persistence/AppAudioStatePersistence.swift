import Foundation

@MainActor
final class AppAudioStatePersistence {
    private let defaults: UserDefaults
    private let storageKey = "AppMixer.appAudioState.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadAppStates() -> [String: AppAudioState] {
        guard let data = defaults.data(forKey: storageKey) else {
            return [:]
        }

        do {
            let records = try JSONDecoder().decode([String: PersistedAppAudioState].self, from: data)
            return records.reduce(into: [:]) { partialResult, item in
                partialResult[item.key] = AppAudioState(
                    appID: item.key,
                    isMuted: false,
                    volume: item.value.volume
                )
            }
        } catch {
            defaults.removeObject(forKey: storageKey)
            return [:]
        }
    }

    func save(_ appStates: [String: AppAudioState]) {
        let records = appStates.reduce(into: [String: PersistedAppAudioState]()) { partialResult, item in
            partialResult[item.key] = PersistedAppAudioState(volume: item.value.volume)
        }

        guard let data = try? JSONEncoder().encode(records) else {
            return
        }

        defaults.set(data, forKey: storageKey)
    }
}

private struct PersistedAppAudioState: Codable {
    let volume: Double
}
