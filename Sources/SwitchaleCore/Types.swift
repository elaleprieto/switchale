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

/// Un modificador y una tecla que abren la Switch Session de un Scope.
public struct Hotkey: Sendable, Equatable {
    public var modifier: Modifiers
    public var key: KeyCode
    /// Si el Hotkey con ⇧ también vale (para retroceder). Si no, con ⇧ pasa al sistema.
    public var reversesWithShift: Bool

    public init(modifier: Modifiers, key: KeyCode, reversesWithShift: Bool) {
        self.modifier = modifier
        self.key = key
        self.reversesWithShift = reversesWithShift
    }

    /// La tecla con el modificador, y ⇧ si el Hotkey retrocede con ⇧; ningún otro modificador.
    func matches(_ key: KeyCode, _ modifiers: Modifiers) -> Bool {
        let allowed: Modifiers = reversesWithShift ? [modifier, .shift] : modifier
        return key == self.key && modifiers.contains(modifier) && modifiers.subtracting(allowed).isEmpty
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

    public init(
        windows: [Window], apps: [AppInfo], focusedWindow: WindowID?, screens: Screens,
        windowlessApps: [AppID] = []
    ) {
        self.windows = windows
        self.apps = apps
        self.focusedWindow = focusedWindow
        self.screens = screens
        self.windowlessApps = windowlessApps
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
