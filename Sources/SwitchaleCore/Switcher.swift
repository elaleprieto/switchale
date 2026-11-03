// Núcleo del switcher: función (estado, evento) → (estado, [efecto]).

/// En qué pantalla aparece el Window Switcher.
public enum PanelScreen: String, Sendable, Equatable {
    /// La pantalla de la Window con foco (por defecto).
    case focusedWindow
    /// La pantalla donde está el mouse.
    case mouse
    /// La pantalla principal del sistema.
    case primary
}

public struct SwitcherConfig: Sendable, Equatable {
    public var allWindowsEnabled: Bool
    /// Incluir las Windows de otras pantallas (por defecto sí).
    public var includeOtherScreens: Bool
    public var panelScreen: PanelScreen
    /// Activation Delay por defecto: 80 ms.
    public var activationDelayMilliseconds: Int

    public init(
        allWindowsEnabled: Bool = true, includeOtherScreens: Bool = true,
        panelScreen: PanelScreen = .focusedWindow, activationDelayMilliseconds: Int = 80
    ) {
        self.allWindowsEnabled = allWindowsEnabled
        self.includeOtherScreens = includeOtherScreens
        self.panelScreen = panelScreen
        self.activationDelayMilliseconds = activationDelayMilliseconds
    }
}

public enum SwitcherEvent: Sendable, Equatable {
    case keyDown(KeyCode, Modifiers, isRepeat: Bool)
    case keyUp(KeyCode)
    /// Estado actual de los modificadores (flagsChanged, o relectura tras reinstalar el tap).
    case modifiersChanged(Modifiers)
    case activationDelayElapsed
    case windowFocused(WindowID)
    /// El efecto `.activate` no pudo activar la Window (se cerró después de la última foto).
    case activationFailed(WindowID)
    case snapshot(Snapshot)
    case configChanged(SwitcherConfig)
}

public enum SwitcherEffect: Sendable, Equatable {
    case startActivationTimer(milliseconds: Int)
    case cancelActivationTimer
    case activate(WindowID)
    /// Pedir una foto fresca de las Windows (de forma asíncrona).
    case refreshSnapshot
    /// El evento de teclado no debe llegar al sistema. Sin este efecto pasa.
    case consumeEvent
    /// Mostrar el Window Switcher con este contenido.
    case showSwitcher(SwitcherContent)
    /// Mover la selección del Window Switcher visible a este índice.
    case selectItem(Int)
    /// Reemplazar el contenido del Window Switcher visible (cambiaron las Windows con él abierto).
    case updateSwitcher(SwitcherContent)
    case hideSwitcher
}

/// Lo que muestra el Window Switcher: sus ítems, el índice seleccionado y la pantalla donde aparece.
public struct SwitcherContent: Sendable, Equatable {
    public var items: [SwitcherItem]
    public var selected: Int
    public var screen: ScreenID

    public init(_ items: [SwitcherItem], selected: Int, screen: ScreenID) {
        self.items = items
        self.selected = selected
        self.screen = screen
    }
}

/// Un ítem del Window Switcher: la Window y lo que hay que mostrar de ella.
public struct SwitcherItem: Sendable, Equatable {
    public var windowID: WindowID
    public var appID: AppID
    /// Título de la Window, o el nombre de la App si la Window no tiene título.
    public var title: String

    public init(windowID: WindowID, appID: AppID, title: String) {
        self.windowID = windowID
        self.appID = appID
        self.title = title
    }
}

public struct SwitcherState: Sendable {
    var config: SwitcherConfig
    var snapshot = Snapshot(
        windows: [], apps: [], focusedWindow: nil, screens: Screens(mouse: ScreenID(0), primary: ScreenID(0))
    )
    /// Recency Order: de la más reciente a la menos reciente.
    var recency: [WindowID] = []
    var session: Session?
    /// Teclas consumidas cuyo keyUp hay que consumir (puede llegar después de terminar la sesión).
    var heldKeys: Set<KeyCode> = []

    struct Session {
        var delayElapsed = false
        /// Pantalla donde aparece el Window Switcher. Se decide con la primera foto de la sesión
        /// (la que pide al arrancar, no la vieja) y no cambia hasta que termina.
        var panelScreen: ScreenID?
        /// Lo que muestra el Window Switcher, o nil si no está visible.
        private var shown: SwitcherContent?
        /// Windows de la Switch Session, en Recency Order.
        var windows: [WindowID]
        var selected: Int
        /// La Switch Session arrancó con ⌘⇧⇥.
        let startsBackwards: Bool

        init(windows: [WindowID], startsBackwards: Bool) {
            self.windows = windows
            self.startsBackwards = startsBackwards
            selected = Self.initialSelection(windows, backwards: startsBackwards)
        }

        var isSwitcherVisible: Bool { shown != nil }

        /// Con ⌘⇥, el segundo ítem en Recency Order (un Quick Switch); con ⌘⇧⇥, el último.
        /// Si hay uno solo, ese.
        private static func initialSelection(_ windows: [WindowID], backwards: Bool) -> Int {
            if backwards { return max(0, windows.count - 1) }
            return windows.count >= 2 ? 1 : 0
        }

        /// Cambian las Windows: la selección sigue a su Window; si esa se fue, queda en la misma
        /// posición (o en la última, si la grilla se achicó).
        mutating func replaceWindows(with newWindows: [WindowID]) {
            if windows.isEmpty {
                selected = Self.initialSelection(newWindows, backwards: startsBackwards)
            } else if let window = selectedWindow, let index = newWindows.firstIndex(of: window) {
                selected = index
            } else {
                selected = max(0, min(selected, newWindows.count - 1))
            }
            windows = newWindows
        }

        var selectedWindow: WindowID? { windows.indices.contains(selected) ? windows[selected] : nil }

        /// Lo que hay que deshacer al terminar la Switch Session.
        var closingEffects: [SwitcherEffect] {
            (delayElapsed ? [] : [.cancelActivationTimer]) + (isSwitcherVisible ? [.hideSwitcher] : [])
        }

        mutating func move(by offset: Int) {
            guard !windows.isEmpty else { return }
            selected = ((selected + offset) % windows.count + windows.count) % windows.count
            shown?.selected = selected
        }

        /// Muestra, actualiza u oculta el Window Switcher para que refleje la sesión en esta foto:
        /// está visible si venció el Activation Delay, ya se decidió la pantalla del panel y hay ítems.
        mutating func syncSwitcher(with snapshot: Snapshot) -> [SwitcherEffect] {
            let items = snapshot.items(for: windows)
            let target = delayElapsed && !items.isEmpty
                ? panelScreen.map { SwitcherContent(items, selected: selected, screen: $0) } : nil
            defer { shown = target }
            switch (shown, target) {
            case (nil, let new?): return [.showSwitcher(new)]
            case (_?, nil): return [.hideSwitcher]
            case (let old?, let new?) where old != new: return [.updateSwitcher(new)]
            default: return []
            }
        }
    }
}

public struct SwitcherCore: Sendable {
    public private(set) var state: SwitcherState

    public init(config: SwitcherConfig = .init()) {
        state = SwitcherState(config: config)
    }

    public mutating func send(_ event: SwitcherEvent) -> [SwitcherEffect] {
        let (next, effects) = Self.reduce(state, event)
        state = next
        return effects
    }

    public static func reduce(_ state: SwitcherState, _ event: SwitcherEvent) -> (SwitcherState, [SwitcherEffect]) {
        var next = state
        switch event {
        case .keyDown(.escape, _, let isRepeat):
            guard let session = next.session else {
                // Autorepeat del Esc que canceló la Switch Session: no tiene que llegarle a la App de adelante.
                let isCancellingEscapeHeld = isRepeat && next.heldKeys.contains(.escape)
                return (next, isCancellingEscapeHeld ? [.consumeEvent] : [])
            }
            next.session = nil
            next.heldKeys.insert(.escape)
            return (next, [.consumeEvent] + session.closingEffects)

        case .keyDown(let key, let modifiers, let isRepeat):
            guard isQuickSwitchHotkey(key, modifiers), next.config.allWindowsEnabled else { return (next, []) }
            next.heldKeys.insert(key)
            if var session = next.session {
                session.move(by: modifiers.contains(.shift) ? -1 : 1)
                next.session = session
                return (next, session.isSwitcherVisible ? [.consumeEvent, .selectItem(session.selected)] : [.consumeEvent])
            }
            guard !isRepeat else { return (next, [.consumeEvent]) }
            next.session = .init(windows: eligibleWindows(next), startsBackwards: modifiers.contains(.shift))
            return (next, [.consumeEvent, .refreshSnapshot, .startActivationTimer(milliseconds: next.config.activationDelayMilliseconds)])

        case .keyUp(let key):
            guard next.heldKeys.remove(key) != nil else { return (next, []) }
            return (next, [.consumeEvent])

        case .modifiersChanged(let modifiers):
            guard let session = next.session, !modifiers.contains(.command) else { return (next, []) }
            next.session = nil
            var effects = session.closingEffects
            if session.windows.count >= 2, let target = session.selectedWindow { effects.append(.activate(target)) }
            return (next, effects)

        case .activationDelayElapsed:
            guard var session = next.session else { return (next, []) }
            session.delayElapsed = true
            let effects = session.syncSwitcher(with: next.snapshot)
            next.session = session
            return (next, effects)

        case .windowFocused(let id):
            next.recency.removeAll { $0 == id }
            next.recency.insert(id, at: 0)
            return (next, [])

        case .activationFailed:
            // No se registra foco en esa Window; la foto nueva la saca de Recency Order si ya no existe.
            return (next, [.refreshSnapshot])

        case .snapshot(let snapshot):
            next.snapshot = snapshot
            let present = Set(snapshot.windows.map(\.id))
            next.recency = next.recency.filter { present.contains($0) }
            let known = Set(next.recency)
            let unknown = snapshot.windows
                .filter { !known.contains($0.id) }
                .sorted { $0.stackIndex < $1.stackIndex }
            next.recency += unknown.map(\.id)
            guard var session = next.session else { return (next, []) }
            session.replaceWindows(with: eligibleWindows(next))
            session.panelScreen = session.panelScreen ?? panelScreen(of: snapshot, config: next.config)
            let effects = session.syncSwitcher(with: next.snapshot)
            next.session = session
            return (next, effects)

        case .configChanged(let config):
            next.config = config
            return (next, [])
        }
    }

    /// ⌘⇥ y ⌘⇧⇥: abren la Switch Session; dentro de ella, avanzan o retroceden la selección.
    private static func isQuickSwitchHotkey(_ key: KeyCode, _ modifiers: Modifiers) -> Bool {
        key == .tab && modifiers.contains(.command) && modifiers.subtracting([.command, .shift]).isEmpty
    }

    /// Pantalla donde aparece el Window Switcher según la configuración. Con `.focusedWindow`, la
    /// pantalla actual de la foto: la de la Window con foco o, si no hay, la del mouse.
    private static func panelScreen(of snapshot: Snapshot, config: SwitcherConfig) -> ScreenID {
        switch config.panelScreen {
        case .mouse: snapshot.screens.mouse
        case .primary: snapshot.screens.primary
        case .focusedWindow: snapshot.currentScreen
        }
    }

    /// Reglas de inclusión: Space actual, sin Minimized ni Windows de Hidden Apps; y la pantalla
    /// actual, salvo que se incluyan las otras pantallas.
    private static func eligibleWindows(_ state: SwitcherState) -> [WindowID] {
        let windowsByID = state.snapshot.windowsByID
        return state.recency.compactMap { id in
            guard let window = windowsByID[id],
                  window.isInCurrentSpace,
                  state.config.includeOtherScreens || window.screen == state.snapshot.currentScreen,
                  !window.isMinimized,
                  !window.isAppHidden
            else { return nil }
            return id
        }
    }
}

extension Snapshot {
    /// Los ítems del Window Switcher para estas Windows, en el mismo orden; las que no están en la
    /// foto se omiten.
    func items(for windows: [WindowID]) -> [SwitcherItem] {
        let windowsByID = windowsByID
        let appNames = Dictionary(apps.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return windows.compactMap { id in
            guard let window = windowsByID[id] else { return nil }
            let title = window.title.isEmpty ? appNames[window.appID] ?? "" : window.title
            return SwitcherItem(windowID: id, appID: window.appID, title: title)
        }
    }
}
