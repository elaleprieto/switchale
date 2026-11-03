import Foundation
import SwitchaleCore

/// Lo que switchale recuerda entre arranques sobre los permisos, en `UserDefaults`:
/// qué permisos ya pidió y si ya arrancó alguna vez.
@MainActor
struct PermissionsHistory {
    private static let hasLaunchedKey = "hasLaunched"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Permisos que switchale ya pidió alguna vez.
    var requested: Set<Permission> {
        Set(Permission.allCases.filter { defaults.bool(forKey: Self.requestedKey($0)) })
    }

    func markRequested(_ permission: Permission) {
        defaults.set(true, forKey: Self.requestedKey(permission))
    }

    /// Devuelve si es el primer arranque y lo deja anotado para los siguientes.
    func recordLaunch() -> Bool {
        let isFirstLaunch = !defaults.bool(forKey: Self.hasLaunchedKey)
        defaults.set(true, forKey: Self.hasLaunchedKey)
        return isFirstLaunch
    }

    private static func requestedKey(_ permission: Permission) -> String {
        switch permission {
        case .accessibility: "requestedAccessibility"
        case .screenRecording: "requestedScreenRecording"
        }
    }
}
