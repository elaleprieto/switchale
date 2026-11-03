import Foundation
import SwitchaleCore

/// Consulta periódicamente los permisos y avisa cuando cambian, así la ventana y
/// el menú se actualizan sin reiniciar la app (macOS no notifica estos cambios).
@MainActor
final class PermissionsMonitor {
    private static let interval: TimeInterval = 1

    private let onChange: (PermissionsState) -> Void
    private var timer: Timer?
    private(set) var state: PermissionsState

    init(onChange: @escaping (PermissionsState) -> Void) {
        self.onChange = onChange
        self.state = SystemPermissions.current()
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        let latest = SystemPermissions.current()
        guard latest != state else { return }
        state = latest
        onChange(latest)
    }
}
