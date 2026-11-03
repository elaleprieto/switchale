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

func snapshot(
    _ windows: [Window], focused: Int? = nil, mouse: ScreenID = mainScreen, primary: ScreenID = mainScreen
) -> Snapshot {
    Snapshot(
        windows: windows,
        apps: Set(windows.map(\.appID)).map { AppInfo(id: $0, name: "app\($0.rawValue)") },
        focusedWindow: focused.map(WindowID.init),
        screens: Screens(mouse: mouse, primary: primary)
    )
}

func core(_ windows: [Window], config: SwitcherConfig = .init()) -> SwitcherCore {
    var core = SwitcherCore(config: config)
    _ = core.send(.snapshot(snapshot(windows)))
    return core
}

/// Quick Switch completo: apretar ⌘⇥ y soltar ⌘ de inmediato; devuelve el efecto de activación.
func quickSwitchTarget(_ core: inout SwitcherCore) -> WindowID? {
    _ = core.send(.keyDown(.tab, [.command], isRepeat: false))
    _ = core.send(.keyUp(.tab))
    for case .activate(let id) in core.send(.modifiersChanged([])) { return id }
    return nil
}

/// La foto que pide la Switch Session al arrancar, con las mismas Windows que la anterior.
func deliverFreshSnapshot(_ core: inout SwitcherCore) {
    _ = core.send(.snapshot(core.state.snapshot))
}
