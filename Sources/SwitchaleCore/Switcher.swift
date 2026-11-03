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
    /// El efecto `.activateApp` no pudo activar la App (terminó después de la última foto).
    case appActivationFailed(AppID)
    case snapshot(Snapshot)
    case configChanged(SwitcherConfig)
}

public enum SwitcherEffect: Sendable, Equatable {
    case startActivationTimer(milliseconds: Int)
    case cancelActivationTimer
    case activate(WindowID)
    /// Activar una Windowless App como el clic en su ícono del Dock (reopen).
    case activateApp(AppID)
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

/// Lo que muestra el Window Switcher: sus ítems y el índice seleccionado.
public struct SwitcherContent: Sendable, Equatable {
    public var items: [SwitcherItem]
    public var selected: Int

    public init(_ items: [SwitcherItem], selected: Int) {
        self.items = items
        self.selected = selected
    }
}

/// Qué es un ítem del Window Switcher: una Window o una Windowless App.
public enum ItemID: Sendable, Hashable {
    case window(WindowID)
    case windowlessApp(AppID)
}

/// Un ítem del Window Switcher.
public struct SwitcherItem: Sendable, Equatable {
    public var id: ItemID
    public var appID: AppID
    /// Título de la Window, o el nombre de la App si la Window no tiene título.
    public var title: String

    public init(id: ItemID, appID: AppID, title: String) {
        self.id = id
        self.appID = appID
        self.title = title
    }
}

/// Los ítems de una Switch Session en orden: primero las Windows en Recency Order, después las
/// Windowless Apps. Toda la aritmética de índices vive acá.
struct ItemList: Equatable {
    private(set) var ids: [ItemID]

    init(windows: [WindowID], windowless: [AppID]) {
        ids = windows.map(ItemID.window) + windowless.map(ItemID.windowlessApp)
    }

    var count: Int { ids.count }

    subscript(index: Int) -> ItemID? { ids.indices.contains(index) ? ids[index] : nil }

    func index(of id: ItemID) -> Int? { ids.firstIndex(of: id) }

    /// Con ⌘⇥, el segundo ítem en Recency Order (un Quick Switch); con ⌘⇧⇥, el último.
    /// Si hay uno solo, ese.
    func initialSelection(backwards: Bool) -> Int {
        if backwards { return max(0, count - 1) }
        return count >= 2 ? 1 : 0
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
        /// Lo que muestra el Window Switcher, o nil si no está visible.
        private var shown: SwitcherContent?
        /// Ítems de la Switch Session.
        var items: ItemList
        var selected: Int
        /// La Switch Session arrancó con ⌘⇧⇥.
        let startsBackwards: Bool

        init(items: ItemList, startsBackwards: Bool) {
            self.items = items
            self.startsBackwards = startsBackwards
            selected = items.initialSelection(backwards: startsBackwards)
        }

        var isSwitcherVisible: Bool { shown != nil }

        var selectedItem: ItemID? { items[selected] }

        /// Cambian los ítems: la selección sigue a su ítem; si ese se fue, queda en la misma
        /// posición (o en la última, si la grilla se achicó).
        mutating func replaceItems(with newItems: ItemList) {
            if items.count == 0 {
                selected = newItems.initialSelection(backwards: startsBackwards)
            } else if let item = selectedItem, let index = newItems.index(of: item) {
                selected = index
            } else {
                selected = max(0, min(selected, newItems.count - 1))
            }
            items = newItems
        }

        /// Lo que hay que deshacer al terminar la Switch Session.
        var closingEffects: [SwitcherEffect] {
            (delayElapsed ? [] : [.cancelActivationTimer]) + (isSwitcherVisible ? [.hideSwitcher] : [])
        }

        mutating func move(by offset: Int) {
            guard items.count > 0 else { return }
            selected = ((selected + offset) % items.count + items.count) % items.count
            shown?.selected = selected
        }

        /// Muestra, actualiza u oculta el Window Switcher para que refleje la sesión en esta foto:
        /// está visible si venció el Activation Delay y hay ítems.
        mutating func syncSwitcher(with snapshot: Snapshot) -> [SwitcherEffect] {
            let content = SwitcherContent(snapshot.items(for: items), selected: selected)
            let target = delayElapsed && !content.items.isEmpty ? content : nil
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
            next.session = .init(items: items(next), startsBackwards: modifiers.contains(.shift))
            return (next, [.consumeEvent, .refreshSnapshot, .startActivationTimer(milliseconds: next.config.activationDelayMilliseconds)])

        case .keyUp(let key):
            guard next.heldKeys.remove(key) != nil else { return (next, []) }
            return (next, [.consumeEvent])

        case .modifiersChanged(let modifiers):
            guard let session = next.session, !modifiers.contains(.command) else { return (next, []) }
            next.session = nil
            var effects = session.closingEffects
            if session.items.count >= 2 {
                switch session.selectedItem {
                case .window(let id)?: effects.append(.activate(id))
                case .windowlessApp(let app)?: effects.append(.activateApp(app))
                case nil: break
                }
            }
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

        case .appActivationFailed:
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
            session.replaceItems(with: items(next))
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

    /// Windowless Apps: las que informa el adaptador y no tienen ninguna Window en la foto.
    /// Solo entran en el Scope All Windows.
    public static func windowlessApps(in snapshot: Snapshot, scope: Scope) -> [AppID] {
        guard scope == .allWindows else { return [] }
        let withWindows = Set(snapshot.windows.map(\.appID))
        return snapshot.windowlessApps.filter { !withWindows.contains($0) }
    }

    /// Los ítems de una Switch Session con la foto actual (hoy siempre en el Scope All Windows).
    private static func items(_ state: SwitcherState) -> ItemList {
        ItemList(
            windows: eligibleWindows(state),
            windowless: windowlessApps(in: state.snapshot, scope: .allWindows)
        )
    }

    /// Reglas fijas de inclusión: Space y pantalla actuales, sin Minimized ni Windows de Hidden Apps.
    private static func eligibleWindows(_ state: SwitcherState) -> [WindowID] {
        let windowsByID = state.snapshot.windowsByID
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

extension Snapshot {
    /// Los ítems del Window Switcher para estos ítems, en el mismo orden; las Windows que no están
    /// en la foto se omiten.
    func items(for list: ItemList) -> [SwitcherItem] {
        let windowsByID = windowsByID
        let appNames = Dictionary(apps.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return list.ids.compactMap { id in
            switch id {
            case .window(let windowID):
                guard let window = windowsByID[windowID] else { return nil }
                let title = window.title.isEmpty ? appNames[window.appID] ?? "" : window.title
                return SwitcherItem(id: id, appID: window.appID, title: title)
            case .windowlessApp(let app):
                return SwitcherItem(id: id, appID: app, title: appNames[app] ?? "")
            }
        }
    }
}
