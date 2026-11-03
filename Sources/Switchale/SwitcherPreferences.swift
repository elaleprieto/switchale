import Foundation
import SwitchaleCore

/// Configuración del Window Switcher guardada en `UserDefaults`. La escribe la ventana de
/// Preferencias (o `defaults write <bundle id> <clave> ...`); el Orchestrator la relee en cada
/// cambio y se la pasa al núcleo. Una clave ausente o inválida vale lo de `SwitcherConfig()`.
enum SwitcherPreferences {
    static func load(defaults: UserDefaults = .standard) -> SwitcherConfig {
        var config = SwitcherConfig()
        for setting in settings {
            if let stored = defaults.object(forKey: setting.key) { setting.read(stored, &config) }
        }
        return config
    }

    static func save(_ config: SwitcherConfig, defaults: UserDefaults = .standard) {
        for setting in settings { defaults.set(setting.write(config), forKey: setting.key) }
    }

    /// Borra todas las claves de configuración: vuelven los valores de la spec (`SwitcherConfig()`).
    static func restoreDefaults(defaults: UserDefaults = .standard) {
        for setting in settings { defaults.removeObject(forKey: setting.key) }
    }

    // MARK: - Claves

    /// Una clave de `UserDefaults` y cómo pasa su valor a la configuración y de vuelta.
    private struct Setting {
        let key: String
        /// Aplica el valor guardado a la configuración; si no es del tipo esperado, no hace nada.
        let read: (Any, inout SwitcherConfig) -> Void
        let write: (SwitcherConfig) -> Any

        init<Stored>(
            _ key: String, get: @escaping (SwitcherConfig) -> Stored, set: @escaping (inout SwitcherConfig, Stored) -> Void
        ) {
            self.key = key
            read = { stored, config in if let value = stored as? Stored { set(&config, value) } }
            write = get
        }

        /// Un valor que se guarda tal cual (Bool).
        static func value<Value>(_ key: String, _ path: WritableKeyPath<SwitcherConfig, Value>) -> Setting {
            Setting(key, get: { $0[keyPath: path] }, set: { $0[keyPath: path] = $1 })
        }

        /// Un valor que se guarda con su nombre (`rawValue`); un nombre desconocido se ignora.
        static func named<Value: RawRepresentable>(_ key: String, _ path: WritableKeyPath<SwitcherConfig, Value>) -> Setting
        where Value.RawValue == String {
            Setting(key, get: { $0[keyPath: path].rawValue }, set: { config, name in
                if let value = Value(rawValue: name) { config[keyPath: path] = value }
            })
        }
    }

    /// Todas las claves. Los nombres son los de la sección "Configuración del Window Switcher" del
    /// README.
    private static var settings: [Setting] {
        Scope.allCases.flatMap { scope in
            [
                // Bool; por defecto true.
                Setting("\(scope.rawValue)Enabled", get: { $0.enabledScopes.contains(scope) }, set: { config, enabled in
                    if enabled { config.enabledScopes.insert(scope) } else { config.enabledScopes.remove(scope) }
                }),
                // `HotkeyModifier`: "command", "option", "control" o "shift".
                .named("\(scope.rawValue)HotkeyModifier", \.hotkeys[scope].modifier),
                // `HotkeyKey`: "tab" o "grave".
                .named("\(scope.rawValue)HotkeyKey", \.hotkeys[scope].key),
            ]
        } + [
            // Int, en milisegundos (`ActivationDelay`); por defecto 80.
            Setting("activationDelayMilliseconds", get: { $0.activationDelay.milliseconds }, set: {
                $0.activationDelay = ActivationDelay(milliseconds: $1)
            }),
            // `PanelScreen`: "focusedWindow" (por defecto), "mouse" o "primary".
            .named("panelScreen", \.panelScreen),
            // Bool; por defecto true.
            .value("includesMinimizedWindows", \.includesMinimizedWindows),
            .value("includesHiddenApps", \.includesHiddenApps),
            .value("includesOtherScreens", \.includesOtherScreens),
            // Int, ancho de la Thumbnail en puntos (`ThumbnailSize`); por defecto 160.
            Setting("thumbnailWidth", get: { $0.thumbnailSize.width }, set: { $0.thumbnailSize = ThumbnailSize(width: $1) }),
        ]
    }
}
