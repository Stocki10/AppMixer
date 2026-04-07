import SwiftUI

struct DeviceSectionView: View {
    @ObservedObject var viewModel: OutputDevicesViewModel

    var body: some View {
        SectionCard(title: "Device") {
            Menu {
                ForEach(viewModel.devices) { device in
                    Button(device.name) {
                        viewModel.selectDevice(id: device.id)
                    }
                }
            } label: {
                HStack {
                    Text(viewModel.currentDeviceName)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
