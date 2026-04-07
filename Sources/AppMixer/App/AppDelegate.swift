import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container = DependencyContainer()

    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        menuBarController = MenuBarController(container: container)
        menuBarController?.start()
    }
}
