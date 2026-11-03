import Foundation
import SwitchaleCore

/// Configuración del Window Switcher guardada en `UserDefaults`. La escribe la ventana de
/// Preferencias (o `defaults write <bundle id> <clave> ...`); el Orchestrator la relee en cada
/// cambio y se la pasa al núcleo. Una clave ausente o inválida vale lo de `SwitcherConfig()`.
enum SwitcherPreferences {
    /// Bool por Scope; por defecto true.
    static func enabledKey(_ scope: Scope) -> String { "\(name(of: scope))Enabled" }
    /// "command", "option", "control" o "shift".
    static func modifierKey(_ scope: Scope) -> String { "\(name(of: scope))HotkeyModifier" }
    /// "tab" o "grave".
    static func keyKey(_ scope: Scope) -> String { "\(name(of: scope))HotkeyKey" }
    /// Int, en milisegundos; por defecto 80.
    static let activationDelayKey = "activationDelayMilliseconds"
    /// "focusedWindow" (por defecto), "mouse" o "primary".
    static let panelScreenKey = "panelScreen"
    /// Bool; por defecto true.
    static let includesMinimizedWindowsKey = "includesMinimizedWindows"
    /// Bool; por defecto true.
    static let includesHiddenAppsKey = "includesHiddenApps"
    /// Bool; por defecto true.
    static let includesOtherScreensKey = "includesOtherScreens"
    /// Int, ancho de la Thumbnail en puntos (`ThumbnailSize.widthRange`); por defecto 160.
    static let thumbnailWidthKey = "thumbnailWidth"

    /// Valores admitidos del Activation Delay en Preferencias, en milisegundos.
    static let activationDelayRange = 0...500

    static func load(defaults: UserDefaults = .standard) -> SwitcherConfig {
        var config = SwitcherConfig()
        for scope in Scope.allCases {
            if defaults.object(forKey: enabledKey(scope)) != nil, !defaults.bool(forKey: enabledKey(scope)) {
                config.enabledScopes.remove(scope)
            }
            let modifier = defaults.string(forKey: modifierKey(scope)).flatMap(modifier(named:))
            let key = defaults.string(forKey: keyKey(scope)).flatMap(key(named:))
            let fallback = scope.defaultHotkey
            config.hotkeys[scope] = Hotkey(modifier: modifier ?? fallback.modifier, key: key ?? fallback.key)
        }
        if defaults.object(forKey: activationDelayKey) != nil {
            let delay = defaults.integer(forKey: activationDelayKey)
            config.activationDelayMilliseconds = min(max(delay, activationDelayRange.lowerBound), activationDelayRange.upperBound)
        }
        config.panelScreen = defaults.string(forKey: panelScreenKey).flatMap(PanelScreen.init(rawValue:)) ?? .focusedWindow
        config.includesMinimizedWindows = bool(defaults, includesMinimizedWindowsKey) ?? config.includesMinimizedWindows
        config.includesHiddenApps = bool(defaults, includesHiddenAppsKey) ?? config.includesHiddenApps
        config.includesOtherScreens = bool(defaults, includesOtherScreensKey) ?? config.includesOtherScreens
        if defaults.object(forKey: thumbnailWidthKey) != nil {
            config.thumbnailSize = ThumbnailSize(width: defaults.integer(forKey: thumbnailWidthKey))
        }
        return config
    }

    static func save(_ config: SwitcherConfig, defaults: UserDefaults = .standard) {
        for scope in Scope.allCases {
            let hotkey = config.hotkey(for: scope)
            defaults.set(config.enabledScopes.contains(scope), forKey: enabledKey(scope))
            defaults.set(name(of: hotkey.modifier), forKey: modifierKey(scope))
            defaults.set(name(of: hotkey.key), forKey: keyKey(scope))
        }
        defaults.set(config.activationDelayMilliseconds, forKey: activationDelayKey)
        defaults.set(config.panelScreen.rawValue, forKey: panelScreenKey)
        defaults.set(config.includesMinimizedWindows, forKey: includesMinimizedWindowsKey)
        defaults.set(config.includesHiddenApps, forKey: includesHiddenAppsKey)
        defaults.set(config.includesOtherScreens, forKey: includesOtherScreensKey)
        defaults.set(config.thumbnailSize.width, forKey: thumbnailWidthKey)
    }

    /// Borra todas las claves de configuración: vuelven los valores de la spec (`SwitcherConfig()`).
    static func restoreDefaults(defaults: UserDefaults = .standard) {
        var keys = [
            activationDelayKey, panelScreenKey, includesMinimizedWindowsKey, includesHiddenAppsKey,
            includesOtherScreensKey, thumbnailWidthKey,
        ]
        for scope in Scope.allCases { keys += [enabledKey(scope), modifierKey(scope), keyKey(scope)] }
        keys.forEach(defaults.removeObject(forKey:))
    }

    // MARK: - Nombres guardados

    private static func name(of scope: Scope) -> String {
        switch scope {
        case .allWindows: "allWindows"
        case .currentApp: "currentApp"
        }
    }

    private static let modifierNames: [(Modifiers, String)] = [
        (.command, "command"), (.option, "option"), (.control, "control"), (.shift, "shift"),
    ]
    private static let keyNames: [(KeyCode, String)] = [(.tab, "tab"), (.grave, "grave")]

    private static func name(of modifier: Modifiers) -> String {
        modifierNames.first { $0.0 == modifier }?.1 ?? "command"
    }

    private static func modifier(named name: String) -> Modifiers? {
        modifierNames.first { $0.1 == name }?.0
    }

    private static func name(of key: KeyCode) -> String {
        keyNames.first { $0.0 == key }?.1 ?? "tab"
    }

    private static func key(named name: String) -> KeyCode? {
        keyNames.first { $0.1 == name }?.0
    }

    private static func bool(_ defaults: UserDefaults, _ key: String) -> Bool? {
        defaults.object(forKey: key) == nil ? nil : defaults.bool(forKey: key)
    }
}
