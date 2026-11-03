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
