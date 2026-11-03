// Núcleo del Window Switcher: Swift puro, sin AppKit, AX ni CoreGraphics.

/// Qué Windows entran en el Window Switcher.
public enum Scope: Sendable, CaseIterable {
    /// Las Windows de todas las Apps.
    case allWindows
    /// Solo las Windows de la App activa.
    case currentApp

    /// El Hotkey del Scope: ⌘⇥ para All Windows, ⌥` para Current App.
    public var hotkey: Hotkey {
        switch self {
        case .allWindows: Hotkey(modifier: .command, key: .tab)
        case .currentApp: Hotkey(modifier: .option, key: .grave)
        }
    }
}

/// Un modificador y una tecla que abren la Switch Session de un Scope.
public struct Hotkey: Sendable, Equatable {
    public var modifier: Modifiers
    public var key: KeyCode

    public init(modifier: Modifiers, key: KeyCode) {
        self.modifier = modifier
        self.key = key
    }

    /// La tecla con el modificador, y opcionalmente ⇧ (para retroceder); ningún otro modificador.
    func matches(_ key: KeyCode, _ modifiers: Modifiers) -> Bool {
        key == self.key && modifiers.contains(modifier) && modifiers.subtracting([modifier, .shift]).isEmpty
    }
}
