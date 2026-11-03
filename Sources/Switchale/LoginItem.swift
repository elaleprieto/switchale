import Foundation
import ServiceManagement
import SwitchaleCore

/// Adaptador del login item (`SMAppService.mainApp`). La decisión de registrar o
/// desregistrar la toma el núcleo (`LaunchAtLogin`).
@MainActor
enum LoginItem {
    /// Clave de la preferencia "iniciar al loguearse" en `UserDefaults`.
    static let preferenceKey = "launchAtLogin"

    /// Alinea el login item con la preferencia del usuario (por defecto, activado).
    static func sync(defaults: UserDefaults = .standard) {
        defaults.register(defaults: [preferenceKey: LaunchAtLogin.enabledByDefault])
        let wanted = defaults.bool(forKey: preferenceKey)
        let service = SMAppService.mainApp

        guard let action = LaunchAtLogin.action(wanted: wanted, status: status(of: service)) else {
            return
        }
        do {
            switch action {
            case .register: try service.register()
            case .unregister: try service.unregister()
            }
        } catch {
            NSLog("switchale: no se pudo actualizar el login item (\(action)): \(error)")
        }
    }

    private static func status(of service: SMAppService) -> LoginItemStatus {
        switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        case .notRegistered: .notRegistered
        @unknown default: .notRegistered
        }
    }
}
