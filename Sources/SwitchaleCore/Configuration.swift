// Núcleo del switcher: Swift puro, sin AppKit, AX ni CoreGraphics.

/// Modificador de un Hotkey.
public enum Modifier: Sendable, Equatable {
    case command, option, control, shift
}

/// Tecla de un Hotkey.
public enum Key: Sendable, Equatable {
    case tab, backtick
}

/// Combinación modificador + tecla que abre el Window Switcher de un Scope.
public struct Hotkey: Sendable, Equatable {
    public var modifier: Modifier
    public var key: Key

    public init(modifier: Modifier, key: Key) {
        self.modifier = modifier
        self.key = key
    }
}

/// Configuración de un Scope: si está activo y con qué Hotkey se abre.
public struct ScopeSettings: Sendable, Equatable {
    public var isEnabled: Bool
    public var hotkey: Hotkey

    public init(isEnabled: Bool, hotkey: Hotkey) {
        self.isEnabled = isEnabled
        self.hotkey = hotkey
    }
}

/// Configuración vigente del Window Switcher.
public struct Configuration: Sendable, Equatable {
    public var allWindows: ScopeSettings
    public var currentApp: ScopeSettings
    public var activationDelayMilliseconds: Int

    public init(allWindows: ScopeSettings, currentApp: ScopeSettings, activationDelayMilliseconds: Int) {
        self.allWindows = allWindows
        self.currentApp = currentApp
        self.activationDelayMilliseconds = activationDelayMilliseconds
    }

    public static let `default` = Configuration(
        allWindows: ScopeSettings(isEnabled: true, hotkey: Hotkey(modifier: .command, key: .tab)),
        currentApp: ScopeSettings(isEnabled: true, hotkey: Hotkey(modifier: .option, key: .backtick)),
        activationDelayMilliseconds: 80
    )
}
