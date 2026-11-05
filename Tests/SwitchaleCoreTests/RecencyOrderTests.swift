import Testing
import SwitchaleCore

/// El Recency Order se observa por la Window que activaría un Quick Switch (la segunda del orden).
@Suite("Recency Order")
struct RecencyOrderTests {
    @Test("Sigue los cambios de foco externos")
    func externalFocus() {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        _ = c.send(.windowFocused(WindowID(3)))
        #expect(quickSwitchTarget(&c) == WindowID(1))
    }

    @Test("Las Windows que no vio recibir foco van al final, en orden de apilamiento")
    func unknownAtEnd() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        _ = c.send(.windowFocused(WindowID(2)))
        // Aparecen 4 (apilada detrás) y 3 (apilada delante): el orden queda 2, 1, 3, 4.
        _ = c.send(.snapshot(snapshot([win(1, stack: 2), win(2, stack: 3), win(3, stack: 0), win(4, stack: 1)])))
        #expect(quickSwitchTarget(&c) == WindowID(1))
        // Tras enfocar 1 el orden es 1, 2, 3, 4; enfocar 2 y 3 deja 3, 2, 1, 4.
        _ = c.send(.windowFocused(WindowID(1)))
        _ = c.send(.windowFocused(WindowID(2)))
        _ = c.send(.windowFocused(WindowID(3)))
        _ = c.send(.windowFocused(WindowID(4)))
        // Orden: 4, 3, 2, 1
        #expect(quickSwitchTarget(&c) == WindowID(3))
    }

    @Test("Una Window desconocida nunca pasa delante de las que recibieron foco")
    func unknownBehindFocused() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        _ = c.send(.windowFocused(WindowID(2)))
        _ = c.send(.snapshot(snapshot([win(1, stack: 1), win(2, stack: 2), win(3, stack: 0)])))
        #expect(quickSwitchTarget(&c) == WindowID(1))
    }

    @Test("Sin foco previo, el orden inicial es el de apilamiento")
    func initialStacking() {
        var c = core([win(7, stack: 1), win(5, stack: 0), win(9, stack: 2)])
        #expect(quickSwitchTarget(&c) == WindowID(7))
    }

    @Test("Una Window enfocada que la foto todavía no tiene: el Quick Switch va a la anterior, no a la siguiente")
    func focusedNotInSnapshotYet() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        _ = c.send(.windowFocused(WindowID(1)))
        _ = c.send(.windowFocused(WindowID(3)))
        #expect(quickSwitchTarget(&c) == WindowID(1))
    }

    @Test("Enfocar una Window que la foto no tiene pide una foto nueva")
    func focusedUnknownRefreshes() {
        var c = core([win(1, stack: 0)])
        #expect(c.send(.windowFocused(WindowID(3))) == [.refreshSnapshot])
        #expect(c.send(.windowFocused(WindowID(1))) == [])
    }

    @Test("Si la foto de la sesión trae la Window enfocada, la selección queda en la anterior")
    func focusedArrivesWithSessionSnapshot() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        _ = c.send(.windowFocused(WindowID(1)))
        _ = c.send(.windowFocused(WindowID(3)))
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        _ = c.send(.snapshot(snapshot([win(1, stack: 1), win(2, stack: 2), win(3, stack: 0)])))
        let shown = shownContent(c.send(.activationDelayElapsed))
        #expect(shown?.items.map(\.id) == [.window(WindowID(3)), .window(WindowID(1)), .window(WindowID(2))])
        #expect(shown?.selected == 1)
    }

    @Test("Una foto vieja que no tiene la Window enfocada no la manda al final del Recency Order")
    func staleSnapshotKeepsFocused() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        _ = c.send(.windowFocused(WindowID(1)))
        _ = c.send(.windowFocused(WindowID(3)))
        _ = c.send(.snapshot(snapshot([win(1, stack: 0), win(2, stack: 1)])))
        _ = c.send(.snapshot(snapshot([win(1, stack: 1), win(2, stack: 2), win(3, stack: 0)])))
        #expect(quickSwitchTarget(&c) == WindowID(1))
    }

    @Test("Con la Window enfocada fuera del Window Switcher, el Quick Switch va a la primera no Minimized")
    func focusedNotInSnapshotSkipsMinimized() {
        var c = core([win(1, stack: 0), win(2, stack: 1, minimized: true), win(4, stack: 2)])
        _ = c.send(.windowFocused(WindowID(4)))
        _ = c.send(.windowFocused(WindowID(2)))
        _ = c.send(.windowFocused(WindowID(1)))
        _ = c.send(.windowFocused(WindowID(3)))
        // Recency Order: 3 (sin foto), 1, 2 (Minimized), 4 → en el Window Switcher: 1, 4, 2.
        #expect(quickSwitchTarget(&c) == WindowID(1))
    }

    @Test("Si se activa una App sin Window con foco (el escritorio), el Quick Switch vuelve a la última Window")
    func appWithoutFocusedWindow() {
        var c = core([win(1, app: 1, stack: 0), win(2, app: 1, stack: 1)])
        _ = c.send(.windowFocused(WindowID(2)))
        _ = c.send(.windowFocused(WindowID(1)))
        _ = c.send(.appActivated(AppID(9)))
        #expect(quickSwitchTarget(&c) == WindowID(1))
    }

    // Recién Minimized: 1 tenía foco, se minimiza y el foco pasa a 2, pero la foto de antes la
    // tiene abierta. Recency Order: 2, 1, 3.
    private func justMinimized() -> SwitcherCore {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        _ = c.send(.windowFocused(WindowID(3)))
        _ = c.send(.windowFocused(WindowID(1)))
        _ = c.send(.windowFocused(WindowID(2)))
        return c
    }

    @Test("Una Window recién Minimized: la foto de la Switch Session la manda al final y la selección va a la anterior abierta")
    func justMinimizedWithPanel() {
        var c = justMinimized()
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        _ = c.send(.snapshot(snapshot([win(1, stack: 2, minimized: true), win(2, stack: 0), win(3, stack: 1)])))
        let shown = shownContent(c.send(.activationDelayElapsed))
        #expect(shown?.items.map(\.id) == [.window(WindowID(2)), .window(WindowID(3)), .window(WindowID(1))])
        #expect(shown?.selected == 1)
    }

    @Test("Una Window recién Minimized: si la foto llega antes de soltar, el Quick Switch va a la anterior abierta")
    func justMinimizedQuickSwitch() {
        var c = justMinimized()
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        _ = c.send(.snapshot(snapshot([win(1, stack: 2, minimized: true), win(2, stack: 0), win(3, stack: 1)])))
        #expect(c.send(.modifiersChanged([])) == [.cancelActivationTimer, .activate(WindowID(3))])
    }

    @Test("Si el usuario ya movió la selección, una foto nueva no la cambia de Window")
    func movedSelectionFollowsItem() {
        var c = justMinimized()
        holdHotkey(&c)
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))  // de 1 a 3
        _ = c.send(.snapshot(snapshot([win(1, stack: 2, minimized: true), win(2, stack: 0), win(3, stack: 1)])))
        #expect(c.send(.modifiersChanged([])) == [.hideSwitcher, .activate(WindowID(3))])
    }

    @Test("Las Windows cerradas salen del Recency Order")
    func closed() {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        _ = c.send(.snapshot(snapshot([win(1, stack: 0), win(3, stack: 1)])))
        #expect(quickSwitchTarget(&c) == WindowID(3))
    }
}
