import Foundation
import SwitchaleCore

/// Configuración del Window Switcher guardada en `UserDefaults`. Todavía no hay control en
/// Preferencias (#12): se cambia con `defaults write <bundle id> <clave> ...`.
enum SwitcherPreferences {
    /// Bool; por defecto true.
    static let includeOtherScreensKey = "includeOtherScreens"
    /// "focusedWindow" (por defecto), "mouse" o "primary".
    static let panelScreenKey = "panelScreen"

    static func load(defaults: UserDefaults = .standard) -> SwitcherConfig {
        var config = SwitcherConfig()
        if defaults.object(forKey: includeOtherScreensKey) != nil {
            config.includeOtherScreens = defaults.bool(forKey: includeOtherScreensKey)
        }
        switch defaults.string(forKey: panelScreenKey) {
        case "mouse": config.panelScreen = .mouse
        case "primary": config.panelScreen = .primary
        default: config.panelScreen = .focusedWindow
        }
        return config
    }
}
