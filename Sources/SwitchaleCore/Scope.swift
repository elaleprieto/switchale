// Núcleo del Window Switcher: Swift puro, sin AppKit, AX ni CoreGraphics.

/// Qué Windows entran en el Window Switcher.
public enum Scope: Sendable, CaseIterable {
    /// Las Windows de todas las Apps.
    case allWindows
    /// Solo las Windows de la App activa.
    case currentApp

    /// El Hotkey por defecto del Scope: ⌘⇥ para All Windows (⌘⇧⇥ retrocede), ⌥` para Current App
    /// (sin retroceso: ⌥⇧` pasa al sistema). El vigente sale de la configuración.
    public var defaultHotkey: Hotkey {
        switch self {
        case .allWindows: Hotkey(modifier: .command, key: .tab)
        case .currentApp: Hotkey(modifier: .option, key: .grave)
        }
    }
}
