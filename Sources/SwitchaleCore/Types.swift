// Tipos de dominio del núcleo: identificadores, teclado y foto de Windows.

public struct WindowID: Sendable, Hashable {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }
}

public struct AppID: Sendable, Hashable {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }
}

public struct ScreenID: Sendable, Hashable {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }
}

public struct KeyCode: Sendable, Hashable {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }

    /// ⇥ (kVK_Tab).
    public static let tab = KeyCode(48)
    /// ` (kVK_ANSI_Grave).
    public static let grave = KeyCode(50)
    /// Esc (kVK_Escape).
    public static let escape = KeyCode(53)
    /// ← (kVK_LeftArrow).
    public static let leftArrow = KeyCode(123)
    /// → (kVK_RightArrow).
    public static let rightArrow = KeyCode(124)
    /// ↓ (kVK_DownArrow).
    public static let downArrow = KeyCode(125)
    /// ↑ (kVK_UpArrow).
    public static let upArrow = KeyCode(126)
}

public struct Modifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = Modifiers(rawValue: 1 << 0)
    public static let shift = Modifiers(rawValue: 1 << 1)
    public static let option = Modifiers(rawValue: 1 << 2)
    public static let control = Modifiers(rawValue: 1 << 3)
}

/// El modificador de un Hotkey. El valor crudo es el nombre con el que se guarda.
public enum HotkeyModifier: String, Sendable, CaseIterable {
    case command, option, control, shift

    public var modifiers: Modifiers {
        switch self {
        case .command: .command
        case .option: .option
        case .control: .control
        case .shift: .shift
        }
    }
}

/// La tecla de un Hotkey. El valor crudo es el nombre con el que se guarda.
public enum HotkeyKey: String, Sendable, CaseIterable {
    case tab, grave

    public var keyCode: KeyCode {
        switch self {
        case .tab: .tab
        case .grave: .grave
        }
    }
}

/// Lo que abre la Switch Session de un Scope: un modificador (⌘, ⌥, ⌃ o ⇧) y una tecla (⇥ o `).
public struct Hotkey: Sendable, Equatable {
    public var modifier: HotkeyModifier
    public var key: HotkeyKey

    public init(modifier: HotkeyModifier, key: HotkeyKey) {
        self.modifier = modifier
        self.key = key
    }

    /// Si el Hotkey con ⇧ también vale (para retroceder): solo con ⇥ y un modificador que no sea ⇧,
    /// como ⌘⇧⇥. Con ` no: ⌥⇧` y ⌘⇧` pasan al sistema.
    public var reversesWithShift: Bool { key == .tab && modifier != .shift }

    /// Si estos modificadores son los del Hotkey con ⇧, el que retrocede. Con ⇧ como modificador
    /// del Hotkey, ⇧ no retrocede: es el Hotkey mismo.
    func isReversed(by modifiers: Modifiers) -> Bool {
        reversesWithShift && modifiers.contains(.shift)
    }

    /// Si el modificador del Hotkey está entre estos modificadores (mientras lo esté, sigue la
    /// Switch Session).
    func isHeld(in modifiers: Modifiers) -> Bool {
        modifiers.contains(modifier.modifiers)
    }

    /// La tecla con el modificador, y ⇧ si el Hotkey retrocede con ⇧; ningún otro modificador.
    func matches(_ key: KeyCode, _ modifiers: Modifiers) -> Bool {
        let allowed: Modifiers = reversesWithShift ? [modifier.modifiers, .shift] : modifier.modifiers
        return key == self.key.keyCode && isHeld(in: modifiers) && modifiers.subtracting(allowed).isEmpty
    }
}

/// El Activation Delay: entre 0 y 500 ms, de a 10 ms. Por defecto, 80 ms.
public struct ActivationDelay: Sendable, Equatable {
    public let milliseconds: Int

    /// Los valores admitidos, en milisegundos.
    public static let range = 0...500
    /// El Activation Delay va de a tantos milisegundos.
    public static let step = 10

    /// El Activation Delay más cercano a estos milisegundos: dentro de `range` y múltiplo de `step`.
    public init(milliseconds: Int = 80) {
        let clamped = min(max(milliseconds, Self.range.lowerBound), Self.range.upperBound)
        self.milliseconds = Int((Double(clamped) / Double(Self.step)).rounded()) * Self.step
    }
}

/// Una App en ejecución.
public struct AppInfo: Sendable, Equatable {
    public var id: AppID
    public var name: String

    public init(id: AppID, name: String) {
        self.id = id
        self.name = name
    }
}

/// Una Window tal como la informa el adaptador (ya filtrada por subrol, tamaño, capa y App regular).
/// Qué Windows entran en cada Switch Session lo decide el núcleo.
public struct Window: Sendable, Equatable {
    public var id: WindowID
    public var appID: AppID
    public var title: String
    public var screen: ScreenID
    public var isInCurrentSpace: Bool
    public var isMinimized: Bool
    public var isAppHidden: Bool
    /// Posición en el orden de apilamiento (0 = al frente).
    public var stackIndex: Int

    public init(
        id: WindowID, appID: AppID, title: String, screen: ScreenID,
        isInCurrentSpace: Bool, isMinimized: Bool, isAppHidden: Bool, stackIndex: Int
    ) {
        self.id = id
        self.appID = appID
        self.title = title
        self.screen = screen
        self.isInCurrentSpace = isInCurrentSpace
        self.isMinimized = isMinimized
        self.isAppHidden = isAppHidden
        self.stackIndex = stackIndex
    }
}

/// Las pantallas que importan en una foto, además de la de la Window con foco.
public struct Screens: Sendable, Equatable {
    /// La pantalla donde está el mouse.
    public var mouse: ScreenID
    /// La pantalla principal del sistema.
    public var primary: ScreenID

    public init(mouse: ScreenID, primary: ScreenID) {
        self.mouse = mouse
        self.primary = primary
    }
}

public struct Snapshot: Sendable, Equatable {
    public var windows: [Window]
    public var apps: [AppInfo]
    /// La Window con foco según AX en el momento de la foto, si hay una.
    public var focusedWindow: WindowID?
    public var screens: Screens
    /// Apps regulares en ejecución que el adaptador no encontró con ninguna Window. El núcleo
    /// descarta las que sí tienen una Window en la foto.
    public var windowlessApps: [AppID]
    /// Si el adaptador pudo ubicar en esta foto qué Windows son de otros Spaces (necesita APIs
    /// privadas, ADR-0002). Si no, el núcleo se comporta como con "Windows de otros Spaces"
    /// desactivada.
    public var locatesOtherSpaces: Bool

    public init(
        windows: [Window], apps: [AppInfo], focusedWindow: WindowID?, screens: Screens,
        windowlessApps: [AppID] = [], locatesOtherSpaces: Bool = false
    ) {
        self.windows = windows
        self.apps = apps
        self.focusedWindow = focusedWindow
        self.screens = screens
        self.windowlessApps = windowlessApps
        self.locatesOtherSpaces = locatesOtherSpaces
    }

    /// La pantalla de la Window con foco; nil si no hay una o no está en la foto.
    var focusedScreen: ScreenID? {
        focusedWindow.flatMap { windowsByID[$0] }?.screen
    }

    /// La pantalla actual: la de la Window con foco o, si no la hay, la del mouse.
    var currentScreen: ScreenID { focusedScreen ?? screens.mouse }

    var windowsByID: [WindowID: Window] {
        Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
    }
}
