import SwiftUI

struct AppRowView: View {
    let app: AudioApp
    let onMuteToggle: (Bool) -> Void
    let onVolumeChange: (Double) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AppIconView(icon: app.icon)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.body)
                    Circle()
                        .fill(app.isActiveAudio ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                }

                Text(app.bundleID ?? app.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                onMuteToggle(!app.isMuted)
            } label: {
                Image(systemName: app.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(.borderless)

            Slider(
                value: Binding(
                    get: { app.volume },
                    set: { onVolumeChange($0) }
                ),
                in: 0 ... 1.5
            )
                .frame(width: 110)
                .disabled(!app.canAdjustVolume)
                .help(app.canAdjustVolume
                    ? "Live single-app gain control. Only one app can be actively controlled at a time."
                    : "Live app-volume routing is unavailable on the current output device.")
        }
    }
}
