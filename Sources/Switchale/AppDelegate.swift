import AppKit
import SwitchaleCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissions: PermissionsProvider = SystemPermissions()
    private var statusBar: StatusBarController?
    private var permissionsWindow: PermissionsWindowController?
    private var monitor: PermissionsMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.sync()

        statusBar = StatusBarController { [weak self] in self?.showPermissionsWindow() }

        let monitor = PermissionsMonitor(provider: permissions) { [weak self] state in
            self?.render(PermissionsGuide(state))
        }
        self.monitor = monitor

        let guide = PermissionsGuide(monitor.state)
        render(guide)
        if guide.showsWindowAtLaunch {
            showPermissionsWindow()
        }
        monitor.start()
    }

    private func render(_ guide: PermissionsGuide) {
        statusBar?.update(guide)
        permissionsWindow?.update(guide)
    }

    private func showPermissionsWindow() {
        if permissionsWindow == nil {
            permissionsWindow = PermissionsWindowController { [weak self] permission in
                self?.permissions.requestAccess(to: permission)
            }
        }
        if let monitor {
            permissionsWindow?.update(PermissionsGuide(monitor.state))
        }
        permissionsWindow?.present()
    }
}
