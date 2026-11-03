@testable import SwitchaleCore

let mainScreen = ScreenID(1)
let otherScreen = ScreenID(2)

func win(
    _ id: Int, app: Int = 1, stack: Int, screen: ScreenID = mainScreen,
    inSpace: Bool = true, minimized: Bool = false, appHidden: Bool = false
) -> Window {
    Window(
        id: WindowID(id), appID: AppID(app), title: "w\(id)", screen: screen,
        isInCurrentSpace: inSpace, isMinimized: minimized, isAppHidden: appHidden, stackIndex: stack
    )
}

/// Foto con las Windows dadas, la Window con foco, las pantallas y las Windowless Apps
/// indicadas (por id de App).
func snapshot(
    _ windows: [Window], focused: Int? = nil, mouse: ScreenID = mainScreen, primary: ScreenID = mainScreen,
    windowless: [Int] = []
) -> Snapshot {
    let appIDs = Set(windows.map(\.appID)).union(windowless.map { AppID($0) })
    return Snapshot(
        windows: windows,
        apps: appIDs.map { AppInfo(id: $0, name: "app\($0.rawValue)") },
        focusedWindow: focused.map(WindowID.init),
        screens: Screens(mouse: mouse, primary: primary),
        windowlessApps: windowless.map { AppID($0) }
    )
}

func core(_ windows: [Window], windowless: [Int] = [], config: SwitcherConfig = .init()) -> SwitcherCore {
    var core = SwitcherCore(config: config)
    _ = core.send(.snapshot(snapshot(windows, windowless: windowless)))
    return core
}

/// Núcleo con esta foto y esta App activa.
func core(
    _ windows: [Window], windowless: [Int] = [], config: SwitcherConfig = .init(), activeApp: Int
) -> SwitcherCore {
    var core = core(windows, windowless: windowless, config: config)
    _ = core.send(.appActivated(AppID(activeApp)))
    return core
}

/// Quick Switch completo: apretar ⌘⇥ y soltar ⌘ de inmediato; devuelve el efecto de activación.
func quickSwitchTarget(_ core: inout SwitcherCore) -> WindowID? {
    _ = core.send(.keyDown(.tab, [.command], isRepeat: false))
    _ = core.send(.keyUp(.tab))
    for case .activate(let id) in core.send(.modifiersChanged([])) { return id }
    return nil
}

/// Config "solo Windows visibles": sin Minimized Windows ni Windows de Hidden Apps.
let visibleOnly = SwitcherConfig(includesMinimizedWindows: false, includesHiddenApps: false)

/// La foto que pide la Switch Session al arrancar, con las mismas Windows que la anterior.
func deliverFreshSnapshot(_ core: inout SwitcherCore) {
    _ = core.send(.snapshot(core.state.snapshot))
}
