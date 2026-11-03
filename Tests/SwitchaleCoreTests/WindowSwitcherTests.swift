import Testing
import SwitchaleCore

/// Abre una Switch Session (⌘⇥) y deja vencer el Activation Delay; devuelve los efectos del vencimiento.
@discardableResult
func holdHotkey(_ core: inout SwitcherCore) -> [SwitcherEffect] {
    _ = core.send(.keyDown(.tab, [.command], isRepeat: false))
    return core.send(.activationDelayElapsed)
}

func item(_ id: Int, app: Int = 1, title: String? = nil) -> SwitcherItem {
    SwitcherItem(windowID: WindowID(id), appID: AppID(app), title: title ?? "w\(id)")
}

@Suite("Window Switcher: visibilidad")
struct WindowSwitcherVisibilityTests {
    @Test("Mantener el Hotkey más allá del Activation Delay muestra el Window Switcher con la selección en el segundo ítem")
    func showsAfterDelay() {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        #expect(holdHotkey(&c) == [.showSwitcher(.init([item(1), item(2), item(3)], selected: 1))])
    }

    @Test("Si la Switch Session arranca con ⌘⇧⇥, la selección empieza en el último ítem")
    func shiftTabStartsAtLast() {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        _ = c.send(.keyDown(.tab, [.command, .shift], isRepeat: false))
        #expect(c.send(.activationDelayElapsed) == [.showSwitcher(.init([item(1), item(2), item(3)], selected: 2))])
        #expect(c.send(.keyDown(.tab, [.command, .shift], isRepeat: false)) == [.consumeEvent, .selectItem(1)])
    }

    @Test("Con un toque rápido no se muestra ni se oculta el Window Switcher")
    func quickSwitchHasNoSwitcher() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        let effects = c.send(.keyDown(.tab, [.command], isRepeat: false)) + c.send(.keyUp(.tab)) + c.send(.modifiersChanged([]))
        #expect(!effects.contains { if case .showSwitcher = $0 { true } else { false } })
        #expect(!effects.contains(.hideSwitcher))
    }

    @Test("Con un solo ítem el Window Switcher se muestra igual, y soltar solo lo oculta")
    func singleItem() {
        var c = core([win(1, stack: 0)])
        #expect(holdHotkey(&c) == [.showSwitcher(.init([item(1)], selected: 0))])
        #expect(c.send(.keyDown(.tab, [.command], isRepeat: false)) == [.consumeEvent, .selectItem(0)])
        #expect(c.send(.modifiersChanged([])) == [.hideSwitcher])
    }

    @Test("Con cero ítems el Window Switcher no aparece, y soltar no hace nada")
    func noItems() {
        var c = core([win(1, stack: 0, minimized: true)], config: visibleOnly)
        #expect(holdHotkey(&c) == [])
        #expect(c.send(.keyDown(.tab, [.command], isRepeat: false)) == [.consumeEvent])
        #expect(c.send(.modifiersChanged([])) == [])
    }

    @Test("Una Window sin título muestra el nombre de su App")
    func untitledShowsAppName() {
        var untitled = win(2, app: 7, stack: 1)
        untitled.title = ""
        var c = core([win(1, stack: 0), untitled])
        #expect(holdHotkey(&c) == [.showSwitcher(.init([item(1), item(2, app: 7, title: "app7")], selected: 1))])
    }
}

@Suite("Window Switcher: navegación")
struct WindowSwitcherNavigationTests {
    @Test("⇥ avanza la selección y da la vuelta al final")
    func tabWraps() {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        holdHotkey(&c)
        #expect(c.send(.keyDown(.tab, [.command], isRepeat: false)) == [.consumeEvent, .selectItem(2)])
        #expect(c.send(.keyDown(.tab, [.command], isRepeat: false)) == [.consumeEvent, .selectItem(0)])
    }

    @Test("⇧⇥ retrocede la selección y da la vuelta al principio")
    func shiftTabWraps() {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        holdHotkey(&c)
        #expect(c.send(.keyDown(.tab, [.command, .shift], isRepeat: false)) == [.consumeEvent, .selectItem(0)])
        #expect(c.send(.keyDown(.tab, [.command, .shift], isRepeat: false)) == [.consumeEvent, .selectItem(2)])
    }

    @Test("El keyUp de cada ⇥ de la Switch Session se consume")
    func everyTabKeyUpConsumed() {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        holdHotkey(&c)
        _ = c.send(.keyUp(.tab))
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        #expect(c.send(.keyUp(.tab)) == [.consumeEvent])
    }

    @Test("Mantener ⇥ apretado sigue avanzando la selección")
    func autorepeatAdvances() {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        holdHotkey(&c)
        #expect(c.send(.keyDown(.tab, [.command], isRepeat: true)) == [.consumeEvent, .selectItem(2)])
    }

    @Test("Soltar el modificador activa la Window seleccionada")
    func releaseActivatesSelection() {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        holdHotkey(&c)
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        #expect(c.send(.modifiersChanged([])) == [.hideSwitcher, .activate(WindowID(3))])
    }

    @Test("⇥ antes del Activation Delay también avanza, sin Window Switcher")
    func tabBeforeDelay() {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        #expect(c.send(.keyDown(.tab, [.command], isRepeat: false)) == [.consumeEvent])
        #expect(c.send(.modifiersChanged([])) == [.cancelActivationTimer, .activate(WindowID(3))])
    }
}

@Suite("Window Switcher: Windows que cambian con el Window Switcher abierto")
struct WindowSwitcherSnapshotTests {
    @Test("Si se cierra otra Window, sale de la grilla y la selección sigue en la misma Window")
    func closedOtherWindow() {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        holdHotkey(&c)
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))  // selección en 3
        #expect(c.send(.snapshot(snapshot([win(2, stack: 0), win(3, stack: 1)])))
            == [.updateSwitcher(.init([item(2), item(3)], selected: 1))])
        #expect(c.send(.modifiersChanged([])) == [.hideSwitcher, .activate(WindowID(3))])
    }

    @Test("Si se cierra la Window seleccionada, la selección pasa a la que ocupa su lugar")
    func closedSelectedWindow() {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        holdHotkey(&c)
        #expect(c.send(.snapshot(snapshot([win(1, stack: 0), win(3, stack: 1)])))
            == [.updateSwitcher(.init([item(1), item(3)], selected: 1))])
        #expect(c.send(.modifiersChanged([])) == [.hideSwitcher, .activate(WindowID(3))])
    }

    @Test("Si se cierra la última Window de la grilla estando seleccionada, la selección pasa a la nueva última")
    func closedLastSelected() {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        holdHotkey(&c)
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))  // selección en 3
        #expect(c.send(.snapshot(snapshot([win(1, stack: 0), win(2, stack: 1)])))
            == [.updateSwitcher(.init([item(1), item(2)], selected: 1))])
    }

    @Test("Si se cierran todas las Windows, el Window Switcher se oculta y soltar no hace nada")
    func allClosed() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        holdHotkey(&c)
        #expect(c.send(.snapshot(snapshot([]))) == [.hideSwitcher])
        #expect(c.send(.modifiersChanged([])) == [])
    }

    @Test("Si queda una sola Window, soltar solo oculta el Window Switcher")
    func oneLeft() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        holdHotkey(&c)
        #expect(c.send(.snapshot(snapshot([win(1, stack: 0)]))) == [.updateSwitcher(.init([item(1)], selected: 0))])
        #expect(c.send(.modifiersChanged([])) == [.hideSwitcher])
    }

    @Test("Una foto sin cambios en la grilla no actualiza el Window Switcher")
    func unchanged() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        holdHotkey(&c)
        #expect(c.send(.snapshot(snapshot([win(1, stack: 0), win(2, stack: 1)]))) == [])
    }

    @Test("La foto fresca que llega antes del Activation Delay se usa al mostrar el Window Switcher")
    func freshSnapshotBeforeDelay() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        #expect(c.send(.snapshot(snapshot([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)]))) == [])
        #expect(c.send(.activationDelayElapsed) == [.showSwitcher(.init([item(1), item(2), item(3)], selected: 1))])
    }

    @Test("Si el Window Switcher no se mostró por no tener ítems y llegan Windows, aparece")
    func appearsWhenWindowsArrive() {
        var c = core([])
        holdHotkey(&c)
        #expect(c.send(.snapshot(snapshot([win(1, stack: 0), win(2, stack: 1)])))
            == [.showSwitcher(.init([item(1), item(2)], selected: 1))])
    }
}

@Suite("Window Switcher: Esc")
struct WindowSwitcherEscapeTests {
    @Test("Esc oculta el Window Switcher y soltar el modificador después no cambia de Window")
    func escapeCancels() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        holdHotkey(&c)
        #expect(c.send(.keyDown(.escape, [.command], isRepeat: false)) == [.consumeEvent, .hideSwitcher])
        #expect(c.send(.keyUp(.escape)) == [.consumeEvent])
        #expect(c.send(.modifiersChanged([])) == [])
    }

    @Test("Esc antes del Activation Delay cancela el temporizador y no muestra el Window Switcher")
    func escapeBeforeDelay() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        #expect(c.send(.keyDown(.escape, [.command], isRepeat: false)) == [.consumeEvent, .cancelActivationTimer])
        #expect(c.send(.activationDelayElapsed) == [])
        #expect(c.send(.modifiersChanged([])) == [])
    }

    @Test("Después de Esc, ⇥ con el modificador todavía apretado abre una Switch Session nueva")
    func tabAfterEscape() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        holdHotkey(&c)
        _ = c.send(.keyDown(.escape, [.command], isRepeat: false))
        #expect(c.send(.keyDown(.tab, [.command], isRepeat: false)).contains(.startActivationTimer(milliseconds: 80)))
    }

    @Test("Mantener Esc apretado después de cancelar no le llega a la App de adelante")
    func escapeAutorepeatConsumed() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        holdHotkey(&c)
        _ = c.send(.keyDown(.escape, [.command], isRepeat: false))
        #expect(c.send(.keyDown(.escape, [.command], isRepeat: true)) == [.consumeEvent])
        #expect(c.send(.keyDown(.escape, [.command], isRepeat: true)) == [.consumeEvent])
        #expect(c.send(.keyUp(.escape)) == [.consumeEvent])
        #expect(c.send(.modifiersChanged([])) == [])
    }

    @Test("Sin Switch Session, Esc pasa al sistema")
    func escapeWithoutSession() {
        var c = core([win(1, stack: 0)])
        #expect(c.send(.keyDown(.escape, [], isRepeat: false)) == [])
        #expect(c.send(.keyUp(.escape)) == [])
    }
}
