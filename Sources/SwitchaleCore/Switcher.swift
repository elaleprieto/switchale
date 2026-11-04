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
    public var hotkeys: ScopeHotkeys
    /// Incluir las Minimized Windows (por defecto sí).
    public var includesMinimizedWindows: Bool
    /// Incluir las Windows de Hidden Apps (por defecto sí).
    public var includesHiddenApps: Bool
    /// Incluir las Windows de otras pantallas (por defecto sí).
    public var includesOtherScreens: Bool
    /// Incluir las Windows de otros Spaces (por defecto no). El adaptador solo las informa con la
    /// opción activada: necesita APIs privadas (ADR-0002).
    public var includesOtherSpaces: Bool
    public var panelScreen: PanelScreen
    public var activationDelay: ActivationDelay

    /// Tamaño de las Thumbnails del Window Switcher.
    public var thumbnailSize: ThumbnailSize

    public init(
        enabledScopes: Set<Scope> = Set(Scope.allCases),
        hotkeys: ScopeHotkeys = ScopeHotkeys(),
        includesMinimizedWindows: Bool = true,
        includesHiddenApps: Bool = true, includesOtherScreens: Bool = true,
        includesOtherSpaces: Bool = false,
        panelScreen: PanelScreen = .focusedWindow, activationDelay: ActivationDelay = ActivationDelay(),
        thumbnailSize: ThumbnailSize = ThumbnailSize()
    ) {
        self.enabledScopes = enabledScopes
        self.hotkeys = hotkeys
        self.includesMinimizedWindows = includesMinimizedWindows
        self.includesHiddenApps = includesHiddenApps
        self.includesOtherScreens = includesOtherScreens
        self.includesOtherSpaces = includesOtherSpaces
        self.panelScreen = panelScreen
        self.activationDelay = activationDelay
        self.thumbnailSize = thumbnailSize
    }

    /// Si el Scope puede usar este Hotkey: ningún otro Scope lo tiene, esté activado o no. Así dos
    /// Scopes nunca comparten Hotkey, tampoco al activar uno desactivado.
    public func isHotkeyAvailable(_ hotkey: Hotkey, for scope: Scope) -> Bool {
        Scope.allCases.allSatisfy { $0 == scope || hotkeys[$0] != hotkey }
    }

    /// El Scope activado cuyo Hotkey es esta tecla con estos modificadores. Si dos Scopes activados
    /// tienen el mismo Hotkey (una configuración escrita a mano: `isHotkeyAvailable` lo evita),
    /// gana el primero de `Scope.allCases`, All Windows.
    func scope(for key: KeyCode, _ modifiers: Modifiers) -> Scope? {
        Scope.allCases.first { enabledScopes.contains($0) && hotkeys[$0].matches(key, modifiers) }
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
    /// El efecto `.activateApp` no pudo activar la App (terminó después de la última foto).
    case appActivationFailed(AppID)
    case snapshot(Snapshot)
    case configChanged(SwitcherConfig)
    /// La vista informa cuántas columnas tiene la grilla del Window Switcher (al mostrarse y cuando
    /// cambian). Un valor menor que 1 se ignora.
    case switcherColumnsChanged(Int)
    /// Clic en la celda de este ítem (Window o Windowless App) en el Window Switcher.
    case itemClicked(ItemID)
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

/// Lo que muestra el Window Switcher: sus ítems, el índice seleccionado, la pantalla donde aparece
/// y el tamaño de sus Thumbnails.
public struct SwitcherContent: Sendable, Equatable {
    public var items: [SwitcherItem]
    public var selected: Int
    public var screen: ScreenID
    public var thumbnailSize: ThumbnailSize

    public init(_ items: [SwitcherItem], selected: Int, screen: ScreenID, thumbnailSize: ThumbnailSize) {
        self.items = items
        self.selected = selected
        self.screen = screen
        self.thumbnailSize = thumbnailSize
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
    /// Marca que muestra el panel.
    public var mark: WindowMark

    public init(id: ItemID, appID: AppID, title: String, mark: WindowMark = .none) {
        self.id = id
        self.appID = appID
        self.title = title
        self.mark = mark
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

    /// Con el Hotkey del Scope, el primer ítem que no es la Window actual (un Quick Switch): el
    /// segundo si el primero es la Window actual, si no el primero. Con el Hotkey del Scope con ⇧
    /// (si el Scope retrocede con ⇧), el último. Si hay uno solo, ese.
    func initialSelection(backwards: Bool, current: CurrentWindow) -> Int {
        if backwards { return max(0, count - 1) }
        return count >= 2 && current.isFirst(of: self) ? 1 : 0
    }
}

/// La Window donde está el usuario, según los cambios de foco. El Quick Switch la saltea solo si es
/// el primer ítem: si la foto todavía no la tiene (una Window recién abierta) o no es una Window (un
/// panel), el primer ítem ya es la anterior.
enum CurrentWindow: Equatable {
    /// Sin cambios de foco todavía: se supone que es la primera del Recency Order.
    case unknown
    case window(WindowID)
    /// La App activa no tiene Window con foco (p. ej. el escritorio del Finder).
    case none

    func isFirst(of items: ItemList) -> Bool {
        switch self {
        case .unknown: true
        case .window(let id): items[0] == .window(id)
        case .none: false
        }
    }
}

/// Marca visual de un ítem que es una Window (las Windowless Apps van sin marca). Si la Window es
/// Minimized y además de una Hidden App, gana `.minimized`: es lo que la distingue de las demás
/// Windows de su App.
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
    var current: CurrentWindow = .unknown
    var session: Session?
    /// Teclas consumidas cuyo keyUp hay que consumir (puede llegar después de terminar la sesión).
    var heldKeys: Set<KeyCode> = []

    struct Session {
        let scope: Scope
        /// El Hotkey con el que arrancó la Switch Session: un cambio de configuración vale desde la
        /// próxima.
        let hotkey: Hotkey
        /// Tamaño de las Thumbnails de la Switch Session; un cambio de configuración vale desde la
        /// próxima.
        let thumbnailSize: ThumbnailSize
        var delayElapsed = false
        /// Pantalla donde aparece el Window Switcher. Se decide con la primera foto de la sesión
        /// (la que pide al arrancar, no la vieja) y no cambia hasta que termina.
        var panelScreen: ScreenID?
        /// Lo que muestra el Window Switcher, o nil si no está visible.
        private var shown: SwitcherContent?
        /// Ítems de la Switch Session.
        var items: ItemList
        var selected: Int
        /// La Switch Session arrancó con el Hotkey del Scope con ⇧ (solo si el Scope retrocede con ⇧).
        let startsBackwards: Bool
        /// Columnas de la grilla del Window Switcher, según la vista; nil hasta que las informe.
        /// Siempre mayor que 0: se valida al recibir `switcherColumnsChanged`.
        var columns: Int?

        init(scope: Scope, config: SwitcherConfig, items: ItemList, startsBackwards: Bool, current: CurrentWindow) {
            self.scope = scope
            hotkey = config.hotkeys[scope]
            thumbnailSize = config.thumbnailSize
            self.items = items
            self.startsBackwards = startsBackwards
            selected = items.initialSelection(backwards: startsBackwards, current: current)
        }

        var isSwitcherVisible: Bool { shown != nil }

        var selectedItem: ItemID? { items[selected] }

        /// Cambian los ítems: la selección sigue a su ítem; si ese se fue, queda en la misma
        /// posición (o en la última, si la grilla se achicó).
        mutating func replaceItems(with newItems: ItemList, current: CurrentWindow) {
            if items.count == 0 {
                selected = newItems.initialSelection(backwards: startsBackwards, current: current)
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

        /// Terminar la Switch Session eligiendo este ítem: una Window se activa; una Windowless App,
        /// como el clic en su ícono del Dock. Con un solo ítem no se activa nada: es donde ya está
        /// el usuario.
        func finishEffects(activating target: ItemID?) -> [SwitcherEffect] {
            guard items.count >= 2, let target else { return closingEffects }
            switch target {
            case .window(let id): return closingEffects + [.activate(id)]
            case .windowlessApp(let app): return closingEffects + [.activateApp(app)]
            }
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
            guard items.count > 0 else { return false }
            select(((selected + offset) % items.count + items.count) % items.count)
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
            guard let columns, selected / columns < (items.count - 1) / columns else { return false }
            select(min(selected + columns, items.count - 1))
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
            let shownItems = snapshot.items(for: items)
            let target = delayElapsed && !shownItems.isEmpty
                ? panelScreen.map { SwitcherContent(shownItems, selected: selected, screen: $0, thumbnailSize: thumbnailSize) } : nil
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
                guard session.hotkey.matches(key, modifiers) else { return (next, []) }
                next.heldKeys.insert(key)
                let moved = session.move(session.hotkey.isReversed(by: modifiers) ? .previous : .next)
                next.session = session
                return (next, session.selectionEffects(moved: moved))
            }
            let config = next.config
            guard let scope = config.scope(for: key, modifiers) else { return (next, []) }
            next.heldKeys.insert(key)
            guard !isRepeat else { return (next, [.consumeEvent]) }
            next.session = .init(
                scope: scope, config: config, items: items(next, scope),
                startsBackwards: config.hotkeys[scope].isReversed(by: modifiers), current: next.current
            )
            return (next, [.consumeEvent, .refreshSnapshot, .startActivationTimer(milliseconds: next.config.activationDelay.milliseconds)])

        case .keyUp(let key):
            guard next.heldKeys.remove(key) != nil else { return (next, []) }
            return (next, [.consumeEvent])

        case .modifiersChanged(let modifiers):
            guard let session = next.session, !session.hotkey.isHeld(in: modifiers) else { return (next, []) }
            next.session = nil
            return (next, session.finishEffects(activating: session.selectedItem))

        case .itemClicked(let id):
            // Igual que soltar el modificador con ese ítem seleccionado.
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
            next.current = .window(id)
            // La activación de la App llega aparte y puede llegar tarde: la App de la Window
            // enfocada ya es la App activa.
            guard let window = next.snapshot.windowsByID[id] else {
                // Una Window recién abierta: la foto todavía no la tiene.
                return (next, [.refreshSnapshot])
            }
            next.activeApp = window.appID
            return (next, [])

        case .appActivated(let app):
            next.activeApp = app
            // Si la App tiene una Window con foco, su `windowFocused` llega después.
            if case .window(let id) = next.current, let window = next.snapshot.windowsByID[id], window.appID != app {
                next.current = .none
            }
            return (next, [])

        case .activationFailed:
            // No se registra foco en esa Window; la foto nueva la saca de Recency Order si ya no existe.
            return (next, [.refreshSnapshot])

        case .appActivationFailed:
            return (next, [.refreshSnapshot])

        case .snapshot(let snapshot):
            next.snapshot = snapshot
            let present = Set(snapshot.windows.map(\.id))
            // La Window actual se queda aunque la foto no la tenga: puede ser anterior a que se
            // abriera (la foto se toma de forma asíncrona). Si no, iría al final del Recency Order.
            next.recency = next.recency.filter { present.contains($0) || next.current == .window($0) }
            let known = Set(next.recency)
            let unknown = snapshot.windows
                .filter { !known.contains($0.id) }
                .sorted { $0.stackIndex < $1.stackIndex }
            next.recency += unknown.map(\.id)
            guard var session = next.session else { return (next, []) }
            session.replaceItems(with: items(next, session.scope), current: next.current)
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

    /// Windowless Apps: las que informa el adaptador y no tienen ninguna Window en la foto.
    /// Solo entran en el Scope All Windows: Current App son las Windows de la App activa.
    public static func windowlessApps(in snapshot: Snapshot, scope: Scope) -> [AppID] {
        guard scope == .allWindows else { return [] }
        let withWindows = Set(snapshot.windows.map(\.appID))
        return snapshot.windowlessApps.filter { !withWindows.contains($0) }
    }

    /// Los ítems de una Switch Session del Scope con la foto actual.
    private static func items(_ state: SwitcherState, _ scope: Scope) -> ItemList {
        ItemList(
            windows: eligibleWindows(state, scope),
            windowless: windowlessApps(in: state.snapshot, scope: scope)
        )
    }

    /// Las Windows del Scope en Recency Order, con las Minimized al final (también en Recency
    /// Order): es más probable que se quiera saltar a una que no lo está. Current App: solo las de
    /// la App activa. Reglas de inclusión: otros Spaces, otras pantallas, Minimized y Hidden Apps
    /// según la configuración (otros Spaces, solo si la foto los ubicó).
    private static func eligibleWindows(_ state: SwitcherState, _ scope: Scope) -> [WindowID] {
        let windowsByID = state.snapshot.windowsByID
        let includesOtherSpaces = state.config.includesOtherSpaces && state.snapshot.locatesOtherSpaces
        let eligible: [Window] = state.recency.compactMap { id in
            guard let window = windowsByID[id],
                  scope == .allWindows || window.appID == state.activeApp,
                  includesOtherSpaces || window.isInCurrentSpace,
                  state.config.includesOtherScreens || window.screen == state.snapshot.currentScreen,
                  state.config.includesMinimizedWindows || !window.isMinimized,
                  state.config.includesHiddenApps || !window.isAppHidden
            else { return nil }
            return window
        }
        return (eligible.filter { !$0.isMinimized } + eligible.filter(\.isMinimized)).map(\.id)
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
                return SwitcherItem(id: id, appID: window.appID, title: title, mark: WindowMark(window))
            case .windowlessApp(let app):
                return SwitcherItem(id: id, appID: app, title: appNames[app] ?? "")
            }
        }
    }
}
