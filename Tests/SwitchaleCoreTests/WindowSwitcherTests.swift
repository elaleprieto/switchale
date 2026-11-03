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
        var c = core([win(1, stack: 0, minimized: true)])
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

/// Abre una Switch Session con `count` Windows y el Window Switcher visible, con la grilla en
/// `columns` columnas y la selección en el índice `selected`.
func gridSession(_ count: Int, columns: Int, selected: Int) -> SwitcherCore {
    var c = core((1...count).map { win($0, stack: $0 - 1) })
    holdHotkey(&c)
    _ = c.send(.switcherColumnsChanged(columns))
    // La sesión arranca en el índice 1 (o 0 si hay un solo ítem); ⇥ avanza de a uno.
    let start = count >= 2 ? 1 : 0
    for _ in 0..<((selected - start + count) % count) { _ = c.send(.keyDown(.tab, [.command], isRepeat: false)) }
    return c
}

/// Aprieta una tecla con ⌘ mantenido.
func press(_ key: KeyCode, _ c: inout SwitcherCore) -> [SwitcherEffect] {
    c.send(.keyDown(key, [.command], isRepeat: false))
}

@Suite("Window Switcher: flechas izquierda y derecha")
struct WindowSwitcherHorizontalArrowTests {
    @Test("→ avanza un ítem, como ⇥, y da la vuelta al final")
    func rightWraps() {
        var c = gridSession(3, columns: 3, selected: 1)
        #expect(press(.rightArrow, &c) == [.consumeEvent, .selectItem(2)])
        #expect(press(.rightArrow, &c) == [.consumeEvent, .selectItem(0)])
    }

    @Test("← retrocede un ítem, como ⇧⇥, y da la vuelta al principio")
    func leftWraps() {
        var c = gridSession(3, columns: 3, selected: 1)
        #expect(press(.leftArrow, &c) == [.consumeEvent, .selectItem(0)])
        #expect(press(.leftArrow, &c) == [.consumeEvent, .selectItem(2)])
    }

    @Test("← y → avanzan por ítem y cruzan de fila")
    func horizontalCrossesRows() {
        var c = gridSession(5, columns: 2, selected: 1)
        #expect(press(.rightArrow, &c) == [.consumeEvent, .selectItem(2)])
        #expect(press(.leftArrow, &c) == [.consumeEvent, .selectItem(1)])
    }

    @Test("Soltar el modificador después de mover con flechas activa la Window seleccionada")
    func releaseAfterArrows() {
        var c = gridSession(3, columns: 3, selected: 1)
        _ = press(.rightArrow, &c)
        #expect(c.send(.modifiersChanged([])) == [.hideSwitcher, .activate(WindowID(3))])
    }

    @Test("Mantener una flecha apretada sigue moviendo la selección, y su keyUp se consume")
    func arrowAutorepeatAndKeyUp() {
        var c = gridSession(3, columns: 3, selected: 1)
        #expect(c.send(.keyDown(.rightArrow, [.command], isRepeat: true)) == [.consumeEvent, .selectItem(2)])
        #expect(c.send(.keyUp(.rightArrow)) == [.consumeEvent])
    }
}

@Suite("Window Switcher: flechas arriba y abajo")
struct WindowSwitcherVerticalArrowTests {
    // Grilla de 7 ítems en 3 columnas:
    //   0 1 2
    //   3 4 5
    //   6

    @Test("↓ baja una fila según las columnas informadas")
    func downMovesOneRow() {
        var c = gridSession(7, columns: 3, selected: 1)
        #expect(press(.downArrow, &c) == [.consumeEvent, .selectItem(4)])
    }

    @Test("↑ sube una fila según las columnas informadas")
    func upMovesOneRow() {
        var c = gridSession(7, columns: 3, selected: 5)
        #expect(press(.upArrow, &c) == [.consumeEvent, .selectItem(2)])
    }

    @Test("En la primera fila ↑ no da la vuelta: no mueve la selección, pero se consume")
    func upOnFirstRow() {
        var c = gridSession(7, columns: 3, selected: 1)
        #expect(press(.upArrow, &c) == [.consumeEvent])
        #expect(c.send(.modifiersChanged([])) == [.hideSwitcher, .activate(WindowID(2))])
    }

    @Test("En la última fila ↓ no da la vuelta: no mueve la selección, pero se consume")
    func downOnLastRow() {
        var c = gridSession(7, columns: 3, selected: 6)
        #expect(press(.downArrow, &c) == [.consumeEvent])
    }

    @Test("Si ↓ apunta a una columna que no existe en la última fila incompleta, va al último ítem")
    func downIntoIncompleteRow() {
        var c = gridSession(7, columns: 3, selected: 5)
        #expect(press(.downArrow, &c) == [.consumeEvent, .selectItem(6)])
        c = gridSession(8, columns: 3, selected: 5)
        #expect(press(.downArrow, &c) == [.consumeEvent, .selectItem(7)])
    }

    @Test("Si ↓ apunta a una columna que existe en la última fila incompleta, va a esa columna")
    func downIntoExistingColumnOfLastRow() {
        var c = gridSession(7, columns: 3, selected: 3)
        #expect(press(.downArrow, &c) == [.consumeEvent, .selectItem(6)])
        c = gridSession(8, columns: 3, selected: 4)
        #expect(press(.downArrow, &c) == [.consumeEvent, .selectItem(7)])
    }

    @Test("Con 1 columna, ↑ y ↓ se mueven de a un ítem sin dar la vuelta")
    func oneColumn() {
        var c = gridSession(3, columns: 1, selected: 1)
        #expect(press(.downArrow, &c) == [.consumeEvent, .selectItem(2)])
        #expect(press(.downArrow, &c) == [.consumeEvent])
        #expect(press(.upArrow, &c) == [.consumeEvent, .selectItem(1)])
        #expect(press(.upArrow, &c) == [.consumeEvent, .selectItem(0)])
        #expect(press(.upArrow, &c) == [.consumeEvent])
    }

    @Test("Con 2 columnas y la última fila incompleta, ↓ desde la columna derecha va al último ítem")
    func twoColumns() {
        // 0 1
        // 2 3
        // 4
        var c = gridSession(5, columns: 2, selected: 1)
        #expect(press(.downArrow, &c) == [.consumeEvent, .selectItem(3)])
        #expect(press(.downArrow, &c) == [.consumeEvent, .selectItem(4)])
        #expect(press(.upArrow, &c) == [.consumeEvent, .selectItem(2)])
    }

    @Test("Con todos los ítems en una sola fila, ↑ y ↓ no mueven la selección")
    func singleRow() {
        var c = gridSession(4, columns: 6, selected: 1)
        #expect(press(.downArrow, &c) == [.consumeEvent])
        #expect(press(.upArrow, &c) == [.consumeEvent])
    }

    @Test("Si la vista informa otras columnas (cambió el layout), ↑ y ↓ usan las nuevas")
    func columnsChange() {
        var c = gridSession(7, columns: 3, selected: 1)
        _ = c.send(.switcherColumnsChanged(2))
        #expect(press(.downArrow, &c) == [.consumeEvent, .selectItem(3)])
    }

    @Test("Mientras la vista no informó columnas, ↑ y ↓ no mueven la selección")
    func noColumnsYet() {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        holdHotkey(&c)
        #expect(press(.downArrow, &c) == [.consumeEvent])
    }

    @Test("Las columnas informadas en una Switch Session no pasan a la siguiente")
    func columnsResetPerSession() {
        var c = gridSession(3, columns: 1, selected: 1)
        _ = c.send(.modifiersChanged([]))
        holdHotkey(&c)
        #expect(press(.downArrow, &c) == [.consumeEvent])
    }
}

@Suite("Window Switcher: flechas sin el Window Switcher visible")
struct WindowSwitcherArrowPassThroughTests {
    @Test("Sin Switch Session, las flechas pasan a la App")
    func noSession() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        #expect(press(.rightArrow, &c) == [])
        #expect(c.send(.keyDown(.downArrow, [], isRepeat: false)) == [])
        #expect(c.send(.keyUp(.downArrow)) == [])
    }

    @Test("Antes del Activation Delay, las flechas pasan a la App y no mueven la selección")
    func beforeDelay() {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        #expect(press(.rightArrow, &c) == [])
        #expect(c.send(.keyUp(.rightArrow)) == [])
        #expect(c.send(.modifiersChanged([])) == [.cancelActivationTimer, .activate(WindowID(2))])
    }

    @Test("Si el Window Switcher no se mostró por no tener ítems, las flechas pasan a la App")
    func noItems() {
        var c = core([])
        holdHotkey(&c)
        #expect(press(.rightArrow, &c) == [])
    }
}

@Suite("Window Switcher: clic")
struct WindowSwitcherClickTests {
    @Test("Clic en una celda activa esa Window y oculta el Window Switcher")
    func clickActivates() {
        var c = gridSession(3, columns: 3, selected: 1)
        #expect(c.send(.windowClicked(WindowID(3))) == [.hideSwitcher, .activate(WindowID(3))])
    }

    @Test("Después del clic la Switch Session terminó: soltar el modificador no hace nada")
    func releaseAfterClick() {
        var c = gridSession(3, columns: 3, selected: 1)
        _ = c.send(.windowClicked(WindowID(1)))
        #expect(c.send(.modifiersChanged([])) == [])
        #expect(press(.rightArrow, &c) == [])
    }

    @Test("El keyUp de ⇥ que llega después del clic se consume")
    func tabKeyUpAfterClick() {
        var c = gridSession(3, columns: 3, selected: 1)
        _ = c.send(.windowClicked(WindowID(1)))
        #expect(c.send(.keyUp(.tab)) == [.consumeEvent])
    }

    @Test("Clic con un solo ítem solo oculta el Window Switcher, igual que soltar el modificador")
    func clickSingleItem() {
        var c = core([win(1, stack: 0)])
        holdHotkey(&c)
        #expect(c.send(.windowClicked(WindowID(1))) == [.hideSwitcher])
    }

    @Test("Clic en una Window que ya no existe: la activación falla y se pide una foto nueva")
    func clickClosedWindow() {
        var c = gridSession(3, columns: 3, selected: 1)
        #expect(c.send(.windowClicked(WindowID(3))) == [.hideSwitcher, .activate(WindowID(3))])
        #expect(c.send(.activationFailed(WindowID(3))) == [.refreshSnapshot])
    }

    @Test("Un clic sin Window Switcher visible no hace nada")
    func clickWithoutSwitcher() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        #expect(c.send(.windowClicked(WindowID(2))) == [])
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        #expect(c.send(.windowClicked(WindowID(2))) == [])
    }
}
