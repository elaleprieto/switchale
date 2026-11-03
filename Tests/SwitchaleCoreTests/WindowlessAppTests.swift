import Testing
import SwitchaleCore

private func windowlessItem(_ app: Int) -> SwitcherItem {
    SwitcherItem(id: .windowlessApp(AppID(app)), appID: AppID(app), title: "app\(app)")
}

@Suite("Windowless Apps")
struct WindowlessAppTests {
    @Test("Las Windowless Apps van siempre después de todas las Windows")
    func afterAllWindows() {
        var c = core([win(1, stack: 0), win(2, app: 2, stack: 1)], windowless: [8, 9])
        #expect(holdHotkey(&c) == [.showSwitcher(.init([item(1), item(2, app: 2), windowlessItem(8), windowlessItem(9)], selected: 1))])
    }

    @Test("Una App deja de ser Windowless cuando abre una Window y pasa a listarse por sus Windows")
    func stopsBeingWindowless() {
        var c = core([win(1, stack: 0)], windowless: [8])
        holdHotkey(&c)
        let effects = c.send(.snapshot(snapshot([win(1, stack: 0), win(5, app: 8, stack: 1)], windowless: [8])))
        #expect(effects == [.updateSwitcher(.init([item(1), item(5, app: 8, title: "w5")], selected: 1))])
    }

    @Test("Soltar el modificador con una Windowless App seleccionada la activa como el Dock")
    func activatesWindowlessApp() {
        var c = core([win(1, stack: 0), win(2, stack: 1)], windowless: [8])
        holdHotkey(&c)
        #expect(c.send(.keyDown(.tab, [.command], isRepeat: false)) == [.consumeEvent, .selectItem(2)])
        #expect(c.send(.keyUp(.tab)) == [.consumeEvent])
        #expect(c.send(.modifiersChanged([])) == [.hideSwitcher, .activateApp(AppID(8))])
    }

    @Test("Un Quick Switch con una Window y una Windowless App activa la Windowless App, su segundo ítem")
    func quickSwitchCountsItems() {
        var c = core([win(1, stack: 0)], windowless: [8])
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        _ = c.send(.keyUp(.tab))
        #expect(c.send(.modifiersChanged([])) == [.cancelActivationTimer, .activateApp(AppID(8))])
    }

    @Test("Un Quick Switch sin Windows y con dos Windowless Apps activa la segunda")
    func quickSwitchOnlyWindowless() {
        var c = core([], windowless: [8, 9])
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        #expect(c.send(.modifiersChanged([])) == [.cancelActivationTimer, .activateApp(AppID(9))])
    }

    @Test("Un Quick Switch con ⌘⇧⇥ sin mover la selección activa el último ítem, aunque sea una Windowless App")
    func shiftQuickSwitchLastItem() {
        var c = core([win(1, stack: 0)], windowless: [8, 9])
        _ = c.send(.keyDown(.tab, [.command, .shift], isRepeat: false))
        #expect(c.send(.modifiersChanged([])) == [.cancelActivationTimer, .activateApp(AppID(9))])
    }

    @Test("Con un solo ítem, que es una Windowless App, el Quick Switch no activa nada")
    func quickSwitchSingleWindowless() {
        var c = core([], windowless: [8])
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        #expect(c.send(.modifiersChanged([])) == [.cancelActivationTimer])
    }

    @Test("Las Windowless Apps solo entran en el Scope All Windows")
    func onlyInAllWindows() {
        let s = snapshot([win(1, stack: 0)], windowless: [8])
        #expect(SwitcherCore.windowlessApps(in: s, scope: .allWindows) == [AppID(8)])
        #expect(SwitcherCore.windowlessApps(in: s, scope: .currentApp) == [])
    }

    @Test("Si la Windowless App activada ya no existe, la activación fallida pide una foto nueva")
    func appActivationFailed() {
        var c = core([], windowless: [8])
        #expect(c.send(.appActivationFailed(AppID(8))) == [.refreshSnapshot])
    }
}
