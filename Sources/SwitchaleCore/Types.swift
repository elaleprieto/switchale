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

public struct Snapshot: Sendable, Equatable {
    public var windows: [Window]
    public var apps: [AppInfo]
    /// La pantalla donde está el usuario ahora.
    public var currentScreen: ScreenID

    public init(windows: [Window], apps: [AppInfo], currentScreen: ScreenID) {
        self.windows = windows
        self.apps = apps
        self.currentScreen = currentScreen
    }

    var windowsByID: [WindowID: Window] {
        Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
    }
}
