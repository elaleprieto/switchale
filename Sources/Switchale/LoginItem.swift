import Foundation
import ServiceManagement
import SwitchaleCore

/// Adaptador del login item (`SMAppService.mainApp`). La decisión de registrar o
/// desregistrar la toma el núcleo (`LaunchAtLogin`).
@MainActor
enum LoginItem {
    /// Clave de la preferencia "iniciar al loguearse" en `UserDefaults`.
    static let preferenceKey = "launchAtLogin"

    /// La preferencia del usuario (por defecto, activado).
    static func isWanted(defaults: UserDefaults = .standard) -> Bool {
        defaults.register(defaults: [preferenceKey: LaunchAtLogin.enabledByDefault])
        return defaults.bool(forKey: preferenceKey)
    }

    /// Guarda la preferencia (toggle de Preferencias) y registra o quita el login item.
    static func setWanted(_ wanted: Bool, defaults: UserDefaults = .standard) {
        defaults.set(wanted, forKey: preferenceKey)
        sync(defaults: defaults)
    }

    /// Vuelve la preferencia a su valor por defecto y alinea el login item.
    static func restoreDefault(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: preferenceKey)
        sync(defaults: defaults)
    }

    /// Alinea el login item con la preferencia del usuario (por defecto, activado).
    static func sync(defaults: UserDefaults = .standard) {
        let wanted = isWanted(defaults: defaults)
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
