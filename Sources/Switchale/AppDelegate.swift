import AppKit
import SwitchaleCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let history = PermissionsHistory()
    private var isFirstLaunch = false
    private var statusBar: StatusBarController?
    private var permissionsWindow: PermissionsWindowController?
    private var monitor: PermissionsMonitor?
    private let orchestrator = Orchestrator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.sync()
        isFirstLaunch = history.recordLaunch()
        orchestrator.start()

        statusBar = StatusBarController { [weak self] in self?.showPermissionsWindow() }
        monitor = PermissionsMonitor { [weak self] _ in self?.render() }

        if render().showsWindowAtLaunch {
            showPermissionsWindow()
        }
        monitor?.start()
    }

    /// Único punto que arma la guía de permisos y actualiza ventana y menú.
    @discardableResult
    private func render() -> PermissionsGuide {
        let guide = PermissionsGuide(
            monitor?.state ?? SystemPermissions.current(),
            requested: history.requested,
            isFirstLaunch: isFirstLaunch
        )
        statusBar?.update(guide)
        permissionsWindow?.update(guide)
        return guide
    }

    private func showPermissionsWindow() {
        if permissionsWindow == nil {
            permissionsWindow = PermissionsWindowController(
                onAction: { [weak self] permission, action in self?.perform(action, for: permission) },
                onRelaunch: { AppRelauncher.relaunch() }
            )
        }
        render()
        permissionsWindow?.present()
    }

    private func perform(_ action: PermissionAction, for permission: Permission) {
        switch action {
        case .request:
            SystemPermissions.request(permission)
            history.markRequested(permission)
            render()
        case .openSettings:
            SystemPermissions.openSettings(for: permission)
        }
    }
}
