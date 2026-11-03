// Núcleo del switcher: función (estado, evento) → (estado, [efecto]).

public struct SwitcherConfig: Sendable, Equatable {
    public var allWindowsEnabled: Bool
    /// Activation Delay por defecto: 80 ms.
    public var activationDelayMilliseconds: Int

    public init(allWindowsEnabled: Bool = true, activationDelayMilliseconds: Int = 80) {
        self.allWindowsEnabled = allWindowsEnabled
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
    /// Mostrar el Window Switcher con estos ítems y el índice seleccionado.
    case showPanel([SwitcherItem], selected: Int)
    /// Mover la selección del panel visible a este índice.
    case selectItem(Int)
    /// Reemplazar los ítems del panel visible (cambiaron las Windows con el panel abierto).
    case updatePanel([SwitcherItem], selected: Int)
    case hidePanel
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
    var snapshot = Snapshot(windows: [], apps: [], currentScreen: ScreenID(0))
    /// Recency Order: de la más reciente a la menos reciente.
    var recency: [WindowID] = []
    var session: Session?
    /// Teclas consumidas cuyo keyUp hay que consumir (puede llegar después de terminar la sesión).
    var heldKeys: Set<KeyCode> = []

    struct Session {
        var delayElapsed = false
        var isPanelVisible = false
        /// Windows de la Switch Session, en Recency Order.
        var items: [WindowID]
        var selected: Int
        /// La Switch Session arrancó con ⌘⇧⇥.
        let startsBackwards: Bool

        init(items: [WindowID], startsBackwards: Bool) {
            self.items = items
            self.startsBackwards = startsBackwards
            selected = Self.initialSelection(items, backwards: startsBackwards)
        }

        /// Con ⌘⇥, el segundo ítem en Recency Order (un Quick Switch); con ⌘⇧⇥, el último.
        /// Si hay uno solo, ese.
        private static func initialSelection(_ items: [WindowID], backwards: Bool) -> Int {
            if backwards { return max(0, items.count - 1) }
            return items.count >= 2 ? 1 : 0
        }

        /// Cambian las Windows: la selección sigue a su Window; si esa se fue, queda en la misma
        /// posición (o en la última, si la grilla se achicó).
        mutating func replaceItems(with newItems: [WindowID]) {
            if items.isEmpty {
                selected = Self.initialSelection(newItems, backwards: startsBackwards)
            } else if let window = selectedWindow, let index = newItems.firstIndex(of: window) {
                selected = index
            } else {
                selected = max(0, min(selected, newItems.count - 1))
            }
            items = newItems
        }

        var selectedWindow: WindowID? { items.indices.contains(selected) ? items[selected] : nil }

        /// Lo que hay que deshacer al terminar la Switch Session.
        var closingEffects: [SwitcherEffect] {
            (delayElapsed ? [] : [.cancelActivationTimer]) + (isPanelVisible ? [.hidePanel] : [])
        }

        mutating func move(by offset: Int) {
            guard !items.isEmpty else { return }
            selected = ((selected + offset) % items.count + items.count) % items.count
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
                return (next, session.isPanelVisible ? [.consumeEvent, .selectItem(session.selected)] : [.consumeEvent])
            }
            guard !isRepeat else { return (next, [.consumeEvent]) }
            next.session = .init(items: eligibleWindows(next), startsBackwards: modifiers.contains(.shift))
            return (next, [.consumeEvent, .refreshSnapshot, .startActivationTimer(milliseconds: next.config.activationDelayMilliseconds)])

        case .keyUp(let key):
            guard next.heldKeys.remove(key) != nil else { return (next, []) }
            return (next, [.consumeEvent])

        case .modifiersChanged(let modifiers):
            guard let session = next.session, !modifiers.contains(.command) else { return (next, []) }
            next.session = nil
            var effects = session.closingEffects
            if session.items.count >= 2, let target = session.selectedWindow { effects.append(.activate(target)) }
            return (next, effects)

        case .activationDelayElapsed:
            guard var session = next.session else { return (next, []) }
            session.delayElapsed = true
            session.isPanelVisible = !session.items.isEmpty
            next.session = session
            guard session.isPanelVisible else { return (next, []) }
            return (next, [.showPanel(items(of: session, in: next.snapshot), selected: session.selected)])

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
            let before = items(of: session, in: state.snapshot)
            session.replaceItems(with: eligibleWindows(next))
            let after = items(of: session, in: next.snapshot)
            let wasVisible = session.isPanelVisible
            session.isPanelVisible = session.delayElapsed && !after.isEmpty
            next.session = session
            switch (wasVisible, session.isPanelVisible) {
            case (false, true): return (next, [.showPanel(after, selected: session.selected)])
            case (true, false): return (next, [.hidePanel])
            case (true, true) where after != before || session.selected != state.session?.selected:
                return (next, [.updatePanel(after, selected: session.selected)])
            default: return (next, [])
            }

        case .configChanged(let config):
            next.config = config
            return (next, [])
        }
    }

    /// ⌘⇥ y ⌘⇧⇥: abren la Switch Session; dentro de ella, avanzan o retroceden la selección.
    private static func isQuickSwitchHotkey(_ key: KeyCode, _ modifiers: Modifiers) -> Bool {
        key == .tab && modifiers.contains(.command) && modifiers.subtracting([.command, .shift]).isEmpty
    }

    private static func items(of session: SwitcherState.Session, in snapshot: Snapshot) -> [SwitcherItem] {
        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.id, $0) })
        let appNames = Dictionary(snapshot.apps.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return session.items.compactMap { id in
            guard let window = windowsByID[id] else { return nil }
            let title = window.title.isEmpty ? appNames[window.appID] ?? "" : window.title
            return SwitcherItem(windowID: id, appID: window.appID, title: title)
        }
    }

    /// Reglas fijas de inclusión: Space y pantalla actuales, sin Minimized ni Windows de Hidden Apps.
    private static func eligibleWindows(_ state: SwitcherState) -> [WindowID] {
        let windowsByID = Dictionary(uniqueKeysWithValues: state.snapshot.windows.map { ($0.id, $0) })
        return state.recency.compactMap { id in
            guard let window = windowsByID[id],
                  window.isInCurrentSpace,
                  window.screen == state.snapshot.currentScreen,
                  !window.isMinimized,
                  !window.isAppHidden
            else { return nil }
            return id
        }
    }
}
