import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let container: DependencyContainer

    init(container: DependencyContainer) {
        self.container = container
        super.init()
    }

    func start() {
        let rootView = MenuBarPopoverView(
            systemOutputViewModel: container.systemOutputViewModel,
            appListViewModel: container.appListViewModel,
            outputDevicesViewModel: container.outputDevicesViewModel,
            settingsViewModel: container.settingsViewModel
        )

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 372, height: 520)
        popover.contentViewController = NSHostingController(rootView: rootView)

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "AppMixer")
            image?.isTemplate = true
            button.image = image
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    @objc
    private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
