import Foundation
import SwitchaleCore

/// Configuración del Window Switcher guardada en `UserDefaults`. Todavía no hay control en
/// Preferencias (#12): se cambia con `defaults write <bundle id> <clave> ...`.
enum SwitcherPreferences {
    /// Bool; por defecto true.
    static let includesOtherScreensKey = "includesOtherScreens"
    /// "focusedWindow" (por defecto), "mouse" o "primary".
    static let panelScreenKey = "panelScreen"

    static func load(defaults: UserDefaults = .standard) -> SwitcherConfig {
        var config = SwitcherConfig()
        if defaults.object(forKey: includesOtherScreensKey) != nil {
            config.includesOtherScreens = defaults.bool(forKey: includesOtherScreensKey)
        }
        config.panelScreen = defaults.string(forKey: panelScreenKey).flatMap(PanelScreen.init(rawValue:)) ?? .focusedWindow
        return config
    }
}
