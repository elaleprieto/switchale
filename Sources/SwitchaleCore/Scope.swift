// Núcleo del Window Switcher: Swift puro, sin AppKit, AX ni CoreGraphics.

/// Qué Windows entran en el Window Switcher. El valor crudo es el nombre con el que se guarda.
public enum Scope: String, Sendable, CaseIterable {
    /// Las Windows de todas las Apps.
    case allWindows
    /// Solo las Windows de la App activa.
    case currentApp
}

/// El Hotkey de cada Scope.
public struct ScopeHotkeys: Sendable, Equatable {
    public var allWindows: Hotkey
    public var currentApp: Hotkey

    /// Por defecto, ⌘⇥ para All Windows (⌘⇧⇥ retrocede) y ⌥` para Current App (sin retroceso:
    /// ⌥⇧` pasa al sistema).
    public init(
        allWindows: Hotkey = Hotkey(modifier: .command, key: .tab),
        currentApp: Hotkey = Hotkey(modifier: .option, key: .grave)
    ) {
        self.allWindows = allWindows
        self.currentApp = currentApp
    }

    public subscript(scope: Scope) -> Hotkey {
        get {
            switch scope {
            case .allWindows: allWindows
            case .currentApp: currentApp
            }
        }
        set {
            switch scope {
            case .allWindows: allWindows = newValue
            case .currentApp: currentApp = newValue
            }
        }
    }
}
