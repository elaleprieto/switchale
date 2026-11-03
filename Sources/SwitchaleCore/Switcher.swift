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
}

public struct SwitcherState: Sendable {
    var config: SwitcherConfig
    var snapshot = Snapshot(windows: [], apps: [], currentScreen: ScreenID(0))
    /// Recency Order: de la más reciente a la menos reciente.
    var recency: [WindowID] = []
    var session: Session?
    /// Tecla del Hotkey cuyo keyUp hay que consumir (puede llegar después de terminar la sesión).
    var heldKey: KeyCode?

    struct Session {
        var delayElapsed = false
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
        case .keyDown(let key, let modifiers, let isRepeat):
            guard isQuickSwitchHotkey(key, modifiers), next.config.allWindowsEnabled else { return (next, []) }
            guard !isRepeat, next.session == nil else { return (next, [.consumeEvent]) }
            next.session = .init()
            next.heldKey = key
            return (next, [.consumeEvent, .refreshSnapshot, .startActivationTimer(milliseconds: next.config.activationDelayMilliseconds)])

        case .keyUp(let key):
            guard next.heldKey == key else { return (next, []) }
            next.heldKey = nil
            return (next, [.consumeEvent])

        case .modifiersChanged(let modifiers):
            guard let session = next.session, !modifiers.contains(.command) else { return (next, []) }
            next.session = nil
            var effects: [SwitcherEffect] = session.delayElapsed ? [] : [.cancelActivationTimer]
            let candidates = eligibleWindows(next)
            if candidates.count >= 2 { effects.append(.activate(candidates[1])) }
            return (next, effects)

        case .activationDelayElapsed:
            next.session?.delayElapsed = true
            return (next, [])

        case .windowFocused(let id):
            next.recency.removeAll { $0 == id }
            next.recency.insert(id, at: 0)
            return (next, [])

        case .snapshot(let snapshot):
            next.snapshot = snapshot
            let present = Set(snapshot.windows.map(\.id))
            next.recency = next.recency.filter { present.contains($0) }
            let known = Set(next.recency)
            let unknown = snapshot.windows
                .filter { !known.contains($0.id) }
                .sorted { $0.stackIndex < $1.stackIndex }
            next.recency += unknown.map(\.id)
            return (next, [])

        case .configChanged(let config):
            next.config = config
            return (next, [])
        }
    }

    /// ⌘⇥ y ⌘⇧⇥ (por ahora Shift no cambia el comportamiento, solo evita el App Switcher nativo).
    private static func isQuickSwitchHotkey(_ key: KeyCode, _ modifiers: Modifiers) -> Bool {
        key == .tab && modifiers.contains(.command) && modifiers.subtracting([.command, .shift]).isEmpty
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
