import SwiftUI

struct OutputSectionView: View {
    @ObservedObject var viewModel: SystemOutputViewModel

    var body: some View {
        SectionCard(title: "Output") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.deviceName)
                        .font(.headline)
                    Text(viewModel.modeDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button {
                        viewModel.toggleMute()
                    } label: {
                        Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .frame(width: 16)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!viewModel.canMute)

                    Slider(
                        value: Binding(
                            get: { viewModel.volume },
                            set: { viewModel.setVolume($0) }
                        ),
                        in: 0 ... 1
                    )

                    Text(viewModel.volumePercentage)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
            }
        }
    }
}
