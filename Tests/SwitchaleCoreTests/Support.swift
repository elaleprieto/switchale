import SwitchaleCore

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

/// Foto con las Windows dadas y las Windowless Apps indicadas (por id de App).
func snapshot(_ windows: [Window], windowless: [Int] = []) -> Snapshot {
    let appIDs = Set(windows.map(\.appID)).union(windowless.map { AppID($0) })
    return Snapshot(
        windows: windows,
        apps: appIDs.map { AppInfo(id: $0, name: "app\($0.rawValue)") },
        currentScreen: mainScreen,
        windowlessApps: windowless.map { AppID($0) }
    )
}

func core(_ windows: [Window], windowless: [Int] = [], config: SwitcherConfig = .init()) -> SwitcherCore {
    var core = SwitcherCore(config: config)
    _ = core.send(.snapshot(snapshot(windows, windowless: windowless)))
    return core
}

/// Quick Switch completo: apretar ⌘⇥ y soltar ⌘ de inmediato; devuelve el efecto de activación.
func quickSwitchTarget(_ core: inout SwitcherCore) -> WindowID? {
    _ = core.send(.keyDown(.tab, [.command], isRepeat: false))
    _ = core.send(.keyUp(.tab))
    for case .activate(let id) in core.send(.modifiersChanged([])) { return id }
    return nil
}
