import Testing
import SwitchaleCore

@Suite("Scope")
struct ScopeTests {
    @Test("Hay exactamente dos Scopes: All Windows y Current App")
    func scopes() {
        #expect(Scope.allCases == [.allWindows, .currentApp])
    }
}

@Suite("Scope Current App")
struct CurrentAppScopeTests {
    @Test("Tocar y soltar ⌥` activa la segunda Window más reciente de la App activa")
    func quickSwitch() {
        var c = core([win(1, app: 1, stack: 0), win(2, app: 2, stack: 1), win(3, app: 1, stack: 2)], activeApp: 1)
        #expect(c.send(.keyDown(.grave, [.option], isRepeat: false))
            == [.consumeEvent, .refreshSnapshot, .startActivationTimer(milliseconds: 80)])
        #expect(c.send(.keyUp(.grave)) == [.consumeEvent])
        #expect(c.send(.modifiersChanged([])) == [.cancelActivationTimer, .activate(WindowID(3))])
    }

    @Test("Mantener ⌥` muestra solo las Windows de la App activa, en Recency Order")
    func switcherShowsActiveAppWindows() {
        var c = core([
            win(1, app: 1, stack: 0), win(2, app: 2, stack: 1), win(3, app: 1, stack: 2), win(4, app: 1, stack: 3),
        ], activeApp: 1)
        _ = c.send(.windowFocused(WindowID(4)))
        _ = c.send(.keyDown(.grave, [.option], isRepeat: false))
        #expect(c.send(.activationDelayElapsed) == [.showSwitcher(.init([item(4), item(1), item(3)], selected: 1))])
        #expect(c.send(.modifiersChanged([])) == [.hideSwitcher, .activate(WindowID(1))])
    }

    @Test("El Scope sigue a la App activa de cada Switch Session")
    func followsActiveApp() {
        var c = core([win(1, app: 1, stack: 0), win(2, app: 2, stack: 1), win(3, app: 1, stack: 2), win(4, app: 2, stack: 3)], activeApp: 1)
        _ = c.send(.appActivated(AppID(2)))
        _ = c.send(.keyDown(.grave, [.option], isRepeat: false))
        #expect(c.send(.activationDelayElapsed) == [.showSwitcher(.init([item(2, app: 2), item(4, app: 2)], selected: 1))])
    }

    @Test("El foco de una Window fija la App activa en la App de esa Window, aunque no haya llegado la activación de la App")
    func windowFocusSetsActiveApp() {
        var c = core([win(1, app: 1, stack: 0), win(2, app: 2, stack: 1), win(3, app: 2, stack: 2)], activeApp: 1)
        _ = c.send(.windowFocused(WindowID(3)))
        _ = c.send(.keyDown(.grave, [.option], isRepeat: false))
        #expect(c.send(.activationDelayElapsed) == [.showSwitcher(.init([item(3, app: 2), item(2, app: 2)], selected: 1))])
    }

    @Test("El foco de una Window que no está en la foto no cambia la App activa")
    func unknownWindowFocusKeepsActiveApp() {
        var c = core([win(1, app: 1, stack: 0), win(2, app: 2, stack: 1), win(3, app: 1, stack: 2)], activeApp: 1)
        _ = c.send(.windowFocused(WindowID(9)))
        _ = c.send(.keyDown(.grave, [.option], isRepeat: false))
        #expect(c.send(.activationDelayElapsed) == [.showSwitcher(.init([item(1), item(3)], selected: 1))])
    }

    @Test("Si la App activa no tiene Windows, no aparece en el Scope: no hay Window Switcher ni activación")
    func windowlessActiveApp() {
        var c = core([win(1, app: 1, stack: 0), win(2, app: 1, stack: 1)], activeApp: 9)
        _ = c.send(.keyDown(.grave, [.option], isRepeat: false))
        #expect(c.send(.activationDelayElapsed) == [])
        #expect(c.send(.modifiersChanged([])) == [])
    }

    @Test("⌥⇧` retrocede: un toque rápido activa la última Window de la App activa")
    func backwards() {
        var c = core([win(1, app: 1, stack: 0), win(2, app: 1, stack: 1), win(3, app: 1, stack: 2), win(4, app: 2, stack: 3)], activeApp: 1)
        _ = c.send(.keyDown(.grave, [.option, .shift], isRepeat: false))
        #expect(c.send(.modifiersChanged([])) == [.cancelActivationTimer, .activate(WindowID(3))])
    }

    @Test("La Switch Session de ⌥` termina al soltar ⌥, no ⌘")
    func endsOnOptionRelease() {
        var c = core([win(1, app: 1, stack: 0), win(2, app: 1, stack: 1)], activeApp: 1)
        _ = c.send(.keyDown(.grave, [.option], isRepeat: false))
        #expect(c.send(.modifiersChanged([.option])) == [])
        #expect(c.send(.modifiersChanged([])) == [.cancelActivationTimer, .activate(WindowID(2))])
    }
}

@Suite("Hotkeys independientes")
struct IndependentHotkeysTests {
    let windows = [win(1, app: 1, stack: 0), win(2, app: 2, stack: 1), win(3, app: 1, stack: 2)]

    @Test("⌘⇥ abre All Windows y ⌥` abre Current App, sobre la misma foto")
    func eachHotkeyOpensItsScope() {
        var c = core(windows, activeApp: 1)
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        #expect(c.send(.activationDelayElapsed) == [.showSwitcher(.init([item(1), item(2, app: 2), item(3)], selected: 1))])
        _ = c.send(.modifiersChanged([]))
        _ = c.send(.keyDown(.grave, [.option], isRepeat: false))
        #expect(c.send(.activationDelayElapsed) == [.showSwitcher(.init([item(1), item(3)], selected: 1))])
    }

    @Test("Con All Windows desactivado, ⌘⇥ pasa al sistema y ⌥` sigue funcionando")
    func allWindowsDisabled() {
        var c = core(windows, config: .init(enabledScopes: [.currentApp]), activeApp: 1)
        #expect(c.send(.keyDown(.tab, [.command], isRepeat: false)) == [])
        #expect(c.send(.modifiersChanged([])) == [])
        _ = c.send(.keyDown(.grave, [.option], isRepeat: false))
        #expect(c.send(.modifiersChanged([])) == [.cancelActivationTimer, .activate(WindowID(3))])
    }

    @Test("Con Current App desactivado, ⌥` pasa al sistema y ⌘⇥ sigue funcionando")
    func currentAppDisabled() {
        var c = core(windows, config: .init(enabledScopes: [.allWindows]), activeApp: 1)
        #expect(c.send(.keyDown(.grave, [.option], isRepeat: false)) == [])
        #expect(c.send(.keyUp(.grave)) == [])
        #expect(c.send(.modifiersChanged([])) == [])
        #expect(quickSwitchTarget(&c) == WindowID(2))
    }

    @Test("Dentro de una Switch Session, el Hotkey del otro Scope no mueve la selección y pasa al sistema")
    func otherHotkeyInsideSession() {
        var c = core(windows, activeApp: 1)
        _ = c.send(.keyDown(.grave, [.option], isRepeat: false))
        _ = c.send(.activationDelayElapsed)
        #expect(c.send(.keyDown(.tab, [.option], isRepeat: false)) == [])
        #expect(c.send(.keyDown(.grave, [.option], isRepeat: false)) == [.consumeEvent, .selectItem(0)])
    }

    @Test("Otras combinaciones con ` pasan al sistema")
    func otherGraveCombos() {
        var c = core(windows, activeApp: 1)
        #expect(c.send(.keyDown(.grave, [], isRepeat: false)) == [])
        #expect(c.send(.keyDown(.grave, [.command], isRepeat: false)) == [])
        #expect(c.send(.keyDown(.grave, [.option, .control], isRepeat: false)) == [])
    }
}
