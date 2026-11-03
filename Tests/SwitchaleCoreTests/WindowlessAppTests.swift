import Testing
import SwitchaleCore

private func windowlessItem(_ app: Int) -> SwitcherItem {
    SwitcherItem(windowID: nil, appID: AppID(app), title: "app\(app)")
}

/// Foto con las Windows dadas y las Apps sin Windows indicadas.
private func snap(_ windows: [Window], windowless: [Int]) -> Snapshot {
    var s = snapshot(windows)
    for app in windowless { s.apps.append(AppInfo(id: AppID(app), name: "app\(app)")) }
    s.windowlessApps = windowless.map { AppID($0) }
    return s
}

private func coreWith(_ s: Snapshot) -> SwitcherCore {
    var c = SwitcherCore()
    _ = c.send(.snapshot(s))
    return c
}

@Suite("Windowless Apps")
struct WindowlessAppTests {
    @Test("Las Windowless Apps van siempre después de todas las Windows")
    func afterAllWindows() {
        var c = coreWith(snap([win(1, stack: 0), win(2, app: 2, stack: 1)], windowless: [8, 9]))
        #expect(holdHotkey(&c) == [.showSwitcher(.init([item(1), item(2, app: 2), windowlessItem(8), windowlessItem(9)], selected: 1))])
    }

    @Test("Una App deja de ser Windowless cuando abre una Window y pasa a listarse por sus Windows")
    func stopsBeingWindowless() {
        var c = coreWith(snap([win(1, stack: 0)], windowless: [8]))
        holdHotkey(&c)
        let effects = c.send(.snapshot(snap([win(1, stack: 0), win(5, app: 8, stack: 1)], windowless: [8])))
        #expect(effects == [.updateSwitcher(.init([item(1), item(5, app: 8, title: "w5")], selected: 0))])
    }

    @Test("Soltar el modificador con una Windowless App seleccionada la activa como el Dock")
    func activatesWindowlessApp() {
        var c = coreWith(snap([win(1, stack: 0)], windowless: [8]))
        holdHotkey(&c)
        #expect(c.send(.keyDown(.tab, [.command], isRepeat: false)) == [.consumeEvent, .selectItem(1)])
        #expect(c.send(.keyUp(.tab)) == [.consumeEvent])
        #expect(c.send(.modifiersChanged([])) == [.hideSwitcher, .activateApp(AppID(8))])
    }

    @Test("Un toque rápido sin Windows no activa una Windowless App")
    func quickTapDoesNotActivate() {
        var c = coreWith(snap([], windowless: [8]))
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        _ = c.send(.keyUp(.tab))
        #expect(c.send(.modifiersChanged([])) == [.cancelActivationTimer])
    }

    @Test("Si la Windowless App activada ya no existe, la activación fallida pide una foto nueva")
    func appActivationFailed() {
        var c = coreWith(snap([], windowless: [8]))
        #expect(c.send(.appActivationFailed(AppID(8))) == [.refreshSnapshot])
    }
}
