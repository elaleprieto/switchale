// Núcleo del switcher: función (estado, evento) → (estado, [efecto]).

public typealias WindowID = Int
public typealias AppID = Int

/// Una Window que cuenta como tal (el adaptador ya filtró subrol, tamaño, capa y App regular).
public struct WindowInfo: Sendable, Equatable {
    public var id: WindowID
    public var appID: AppID
    public var title: String
    public var isMinimized: Bool
    public var isAppHidden: Bool
    /// Posición en el orden de apilamiento (0 = al frente).
    public var stackIndex: Int

    public init(id: WindowID, appID: AppID, title: String, isMinimized: Bool, isAppHidden: Bool, stackIndex: Int) {
        self.id = id
        self.appID = appID
        self.title = title
        self.isMinimized = isMinimized
        self.isAppHidden = isAppHidden
        self.stackIndex = stackIndex
    }
}

public struct Snapshot: Sendable, Equatable {
    public var windows: [WindowInfo]
    public init(windows: [WindowInfo]) { self.windows = windows }
}

public struct SwitcherConfig: Sendable, Equatable {
    public var allWindowsEnabled: Bool
    public var currentAppEnabled: Bool

    public init(allWindowsEnabled: Bool = true, currentAppEnabled: Bool = true) {
        self.allWindowsEnabled = allWindowsEnabled
        self.currentAppEnabled = currentAppEnabled
    }
}

public enum SwitcherEvent: Sendable, Equatable {
    case hotkeyPressed(Scope)
    case modifierReleased
    case activationDelayElapsed
    case windowFocused(WindowID)
    case snapshot(Snapshot)
    case configChanged(SwitcherConfig)
}

public enum SwitcherEffect: Sendable, Equatable {
    case startActivationTimer
    case cancelActivationTimer
    case activate(WindowID)
    /// El evento de teclado original debe llegar al sistema.
    case passEventToSystem
}

public struct SwitcherState: Sendable {
    var config: SwitcherConfig
    var snapshot = Snapshot(windows: [])
    /// Recency Order: de la más reciente a la menos reciente.
    var recency: [WindowID] = []
    var session: Session?

    struct Session {
        var items: [WindowID]
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
        var s = state
        switch event {
        case .hotkeyPressed(let scope):
            let enabled = scope == .allWindows ? s.config.allWindowsEnabled : s.config.currentAppEnabled
            guard enabled else { return (s, [.passEventToSystem]) }
            guard s.session == nil else { return (s, []) }
            let items = items(s, scope: scope)
            guard !items.isEmpty else { return (s, []) }
            s.session = .init(items: items)
            return (s, [.startActivationTimer])

        case .modifierReleased:
            guard let session = s.session else { return (s, []) }
            s.session = nil
            var effects: [SwitcherEffect] = session.delayElapsed ? [] : [.cancelActivationTimer]
            if session.items.count >= 2 { effects.append(.activate(session.items[1])) }
            return (s, effects)

        case .activationDelayElapsed:
            s.session?.delayElapsed = true
            return (s, [])

        case .windowFocused(let id):
            s.recency.removeAll { $0 == id }
            s.recency.insert(id, at: 0)
            return (s, [])

        case .snapshot(let snap):
            s.snapshot = snap
            let present = Set(snap.windows.map(\.id))
            s.recency = s.recency.filter { present.contains($0) }
            let known = Set(s.recency)
            let unknown = snap.windows.filter { !known.contains($0.id) }.sorted { $0.stackIndex < $1.stackIndex }
            s.recency += unknown.map(\.id)
            return (s, [])

        case .configChanged(let config):
            s.config = config
            return (s, [])
        }
    }

    private static func items(_ s: SwitcherState, scope: Scope) -> [WindowID] {
        let byID = Dictionary(s.snapshot.windows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let ordered = s.recency.compactMap { byID[$0] }
        switch scope {
        case .allWindows:
            return ordered.map(\.id)
        case .currentApp:
            guard let app = ordered.first?.appID else { return [] }
            return ordered.filter { $0.appID == app }.map(\.id)
        }
    }
}
