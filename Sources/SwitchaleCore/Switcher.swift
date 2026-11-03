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
    /// Los Scopes activados. Un Scope desactivado no abre Switch Sessions: su Hotkey hace lo que
    /// hace en macOS.
    public var enabledScopes: Set<Scope>
    /// Incluir las Minimized Windows (por defecto sí).
    public var includesMinimizedWindows: Bool
    /// Incluir las Windows de Hidden Apps (por defecto sí).
    public var includesHiddenApps: Bool
    /// Incluir las Windows de otras pantallas (por defecto sí).
    public var includesOtherScreens: Bool
    public var panelScreen: PanelScreen
    /// Activation Delay por defecto: 80 ms.
    public var activationDelayMilliseconds: Int

    public init(
        enabledScopes: Set<Scope> = Set(Scope.allCases), includesMinimizedWindows: Bool = true,
        includesHiddenApps: Bool = true, includesOtherScreens: Bool = true,
        panelScreen: PanelScreen = .focusedWindow, activationDelayMilliseconds: Int = 80
    ) {
        self.enabledScopes = enabledScopes
        self.includesMinimizedWindows = includesMinimizedWindows
        self.includesHiddenApps = includesHiddenApps
        self.includesOtherScreens = includesOtherScreens
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
    /// Pasó a ser la App activa (la de adelante), tenga Windows o no.
    case appActivated(AppID)
    /// El efecto `.activate` no pudo activar la Window (se cerró después de la última foto).
    case activationFailed(WindowID)
    case snapshot(Snapshot)
    case configChanged(SwitcherConfig)
    /// La vista informa cuántas columnas tiene la grilla del Window Switcher (al mostrarse y cuando
    /// cambian). Un valor menor que 1 se ignora.
    case switcherColumnsChanged(Int)
    /// Clic en la celda de esta Window en el Window Switcher.
    case windowClicked(WindowID)
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
    /// Marca que muestra el panel.
    public var mark: WindowMark

    public init(windowID: WindowID, appID: AppID, title: String, mark: WindowMark = .none) {
        self.windowID = windowID
        self.appID = appID
        self.title = title
        self.mark = mark
    }
}

/// Marca visual de un ítem. Si la Window es Minimized y además de una Hidden App, gana `.minimized`:
/// es lo que la distingue de las demás Windows de su App.
public enum WindowMark: Sendable, Equatable {
    case none
    case minimized
    case appHidden

    init(_ window: Window) {
        self = window.isMinimized ? .minimized : (window.isAppHidden ? .appHidden : .none)
    }
}

/// Hacia dónde se mueve la selección del Window Switcher.
enum Direction {
    /// El ítem anterior (⇧⇥, ←), con vuelta al final.
    case previous
    /// El ítem siguiente (⇥, →), con vuelta al principio.
    case next
    /// Una fila arriba (↑), sin vuelta.
    case up
    /// Una fila abajo (↓), sin vuelta.
    case down
}

public struct SwitcherState: Sendable {
    var config: SwitcherConfig
    var snapshot = Snapshot(
        windows: [], apps: [], focusedWindow: nil, screens: Screens(mouse: ScreenID(0), primary: ScreenID(0))
    )
    /// Recency Order: de la más reciente a la menos reciente.
    var recency: [WindowID] = []
    /// La App activa, que define el Scope Current App.
    var activeApp: AppID?
    var session: Session?
    /// Teclas consumidas cuyo keyUp hay que consumir (puede llegar después de terminar la sesión).
    var heldKeys: Set<KeyCode> = []

    struct Session {
        let scope: Scope
        var delayElapsed = false
        /// Pantalla donde aparece el Window Switcher. Se decide con la primera foto de la sesión
        /// (la que pide al arrancar, no la vieja) y no cambia hasta que termina.
        var panelScreen: ScreenID?
        /// Lo que muestra el Window Switcher, o nil si no está visible.
        private var shown: SwitcherContent?
        /// Windows de la Switch Session, en Recency Order.
        var windows: [WindowID]
        var selected: Int
        /// La Switch Session arrancó con el Hotkey del Scope con ⇧ (solo si el Scope retrocede con ⇧).
        let startsBackwards: Bool
        /// Columnas de la grilla del Window Switcher, según la vista; nil hasta que las informe.
        /// Siempre mayor que 0: se valida al recibir `switcherColumnsChanged`.
        var columns: Int?

        init(scope: Scope, windows: [WindowID], startsBackwards: Bool) {
            self.scope = scope
            self.windows = windows
            self.startsBackwards = startsBackwards
            selected = Self.initialSelection(windows, backwards: startsBackwards)
        }

        var isSwitcherVisible: Bool { shown != nil }

        /// Con el Hotkey del Scope, el segundo ítem en Recency Order (un Quick Switch); con el
        /// Hotkey del Scope con ⇧ (si el Scope retrocede con ⇧), el último. Si hay uno solo, ese.
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

        /// Terminar la Switch Session eligiendo esta Window. Con un solo ítem no se activa nada:
        /// es la Window en la que ya está el usuario.
        func finishEffects(activating target: WindowID?) -> [SwitcherEffect] {
            guard windows.count >= 2, let target else { return closingEffects }
            return closingEffects + [.activate(target)]
        }

        /// Mueve la selección y devuelve si quedó en un ítem. Anterior y siguiente dan la vuelta en
        /// los extremos; arriba y abajo no.
        mutating func move(_ direction: Direction) -> Bool {
            switch direction {
            case .previous: return step(by: -1)
            case .next: return step(by: 1)
            case .up: return moveUp()
            case .down: return moveDown()
            }
        }

        private mutating func step(by offset: Int) -> Bool {
            guard !windows.isEmpty else { return false }
            select(((selected + offset) % windows.count + windows.count) % windows.count)
            return true
        }

        /// Sube una fila según las columnas que informó la vista; en la primera fila no se mueve.
        private mutating func moveUp() -> Bool {
            guard let columns, selected >= columns else { return false }
            select(selected - columns)
            return true
        }

        /// Baja una fila según las columnas que informó la vista; en la última fila no se mueve.
        /// Si cae en una columna que no existe en la última fila (incompleta), va al último ítem.
        private mutating func moveDown() -> Bool {
            guard let columns, selected / columns < (windows.count - 1) / columns else { return false }
            select(min(selected + columns, windows.count - 1))
            return true
        }

        /// Los efectos de una tecla que mueve la selección: se consume siempre, y el Window Switcher
        /// visible marca la nueva selección si se movió.
        func selectionEffects(moved: Bool) -> [SwitcherEffect] {
            moved && isSwitcherVisible ? [.consumeEvent, .selectItem(selected)] : [.consumeEvent]
        }

        private mutating func select(_ index: Int) {
            selected = index
            shown?.selected = index
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
            if let direction = arrowDirections[key] {
                // Las flechas solo se consumen con el Window Switcher visible; si no, pasan a la App.
                guard var session = next.session, session.isSwitcherVisible else { return (next, []) }
                next.heldKeys.insert(key)
                let moved = session.move(direction)
                next.session = session
                return (next, session.selectionEffects(moved: moved))
            }
            // Dentro de una Switch Session, el Hotkey de su Scope mueve la selección (con ⇧ retrocede, si
            // el Scope lo admite).
            if var session = next.session {
                guard session.scope.hotkey.matches(key, modifiers) else { return (next, []) }
                next.heldKeys.insert(key)
                let moved = session.move(modifiers.contains(.shift) ? .previous : .next)
                next.session = session
                return (next, session.selectionEffects(moved: moved))
            }
            guard let scope = Scope.allCases.first(where: { next.config.enabledScopes.contains($0) && $0.hotkey.matches(key, modifiers) })
            else { return (next, []) }
            next.heldKeys.insert(key)
            guard !isRepeat else { return (next, [.consumeEvent]) }
            next.session = .init(scope: scope, windows: eligibleWindows(next, scope), startsBackwards: modifiers.contains(.shift))
            return (next, [.consumeEvent, .refreshSnapshot, .startActivationTimer(milliseconds: next.config.activationDelayMilliseconds)])

        case .keyUp(let key):
            guard next.heldKeys.remove(key) != nil else { return (next, []) }
            return (next, [.consumeEvent])

        case .modifiersChanged(let modifiers):
            guard let session = next.session, !modifiers.contains(session.scope.hotkey.modifier) else { return (next, []) }
            next.session = nil
            return (next, session.finishEffects(activating: session.selectedWindow))

        case .windowClicked(let id):
            // Igual que soltar el modificador con esa Window seleccionada.
            guard let session = next.session, session.isSwitcherVisible else { return (next, []) }
            next.session = nil
            return (next, session.finishEffects(activating: id))

        case .activationDelayElapsed:
            guard var session = next.session else { return (next, []) }
            session.delayElapsed = true
            let effects = session.syncSwitcher(with: next.snapshot)
            next.session = session
            return (next, effects)

        case .windowFocused(let id):
            next.recency.removeAll { $0 == id }
            next.recency.insert(id, at: 0)
            // La activación de la App llega aparte y puede llegar tarde: la App de la Window
            // enfocada ya es la App activa.
            if let window = next.snapshot.windowsByID[id] { next.activeApp = window.appID }
            return (next, [])

        case .appActivated(let app):
            next.activeApp = app
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
            session.replaceWindows(with: eligibleWindows(next, session.scope))
            session.panelScreen = session.panelScreen ?? panelScreen(of: snapshot, config: next.config)
            let effects = session.syncSwitcher(with: next.snapshot)
            next.session = session
            return (next, effects)

        case .configChanged(let config):
            next.config = config
            return (next, [])

        case .switcherColumnsChanged(let columns):
            // Una grilla sin columnas no existe: se ignora y quedan las anteriores.
            guard columns > 0 else { return (next, []) }
            next.session?.columns = columns
            return (next, [])
        }
    }

    /// ← y → se mueven como ⇧⇥ y ⇥; ↑ y ↓, una fila de la grilla.
    private static let arrowDirections: [KeyCode: Direction] = [
        .leftArrow: .previous, .rightArrow: .next, .upArrow: .up, .downArrow: .down,
    ]

    /// Pantalla donde aparece el Window Switcher según la configuración. Con `.focusedWindow`, la
    /// pantalla actual de la foto: la de la Window con foco o, si no hay, la del mouse.
    private static func panelScreen(of snapshot: Snapshot, config: SwitcherConfig) -> ScreenID {
        switch config.panelScreen {
        case .mouse: snapshot.screens.mouse
        case .primary: snapshot.screens.primary
        case .focusedWindow: snapshot.currentScreen
        }
    }

    /// Las Windows del Scope en Recency Order. Current App: solo las de la App activa.
    /// Reglas de inclusión: Space actual fijo; Minimized, Hidden Apps y otras pantallas según la
    /// configuración.
    private static func eligibleWindows(_ state: SwitcherState, _ scope: Scope) -> [WindowID] {
        let windowsByID = state.snapshot.windowsByID
        return state.recency.compactMap { id in
            guard let window = windowsByID[id],
                  scope == .allWindows || window.appID == state.activeApp,
                  window.isInCurrentSpace,
                  state.config.includesOtherScreens || window.screen == state.snapshot.currentScreen,
                  state.config.includesMinimizedWindows || !window.isMinimized,
                  state.config.includesHiddenApps || !window.isAppHidden
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
            return SwitcherItem(
                windowID: id, appID: window.appID, title: title, mark: WindowMark(window)
            )
        }
    }
}
