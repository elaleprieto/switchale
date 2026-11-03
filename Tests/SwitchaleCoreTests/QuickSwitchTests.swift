import Testing
import SwitchaleCore

private func win(_ id: Int, app: Int = 1, stack: Int) -> WindowInfo {
    WindowInfo(id: id, appID: app, title: "w\(id)", isMinimized: false, isAppHidden: false, stackIndex: stack)
}

private func core(_ windows: [WindowInfo], config: SwitcherConfig = .init()) -> SwitcherCore {
    var c = SwitcherCore(config: config)
    _ = c.send(.snapshot(Snapshot(windows: windows)))
    return c
}

@Suite("Quick Switch")
struct QuickSwitchTests {
    @Test("Tocar y soltar el Hotkey antes del Activation Delay activa la segunda Window, sin panel")
    func quickSwitch() {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        #expect(c.send(.hotkeyPressed(.allWindows)) == [.startActivationTimer])
        #expect(c.send(.modifierReleased) == [.cancelActivationTimer, .activate(2)])
    }

    @Test("Quick Switch alterna entre las dos Windows más recientes, aun de la misma App")
    func toggles() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        _ = c.send(.hotkeyPressed(.allWindows))
        #expect(c.send(.modifierReleased) == [.cancelActivationTimer, .activate(2)])
        _ = c.send(.windowFocused(2))
        _ = c.send(.hotkeyPressed(.allWindows))
        #expect(c.send(.modifierReleased) == [.cancelActivationTimer, .activate(1)])
    }

    @Test("Si vence el Activation Delay, soltar activa la segunda Window y no cancela el temporizador")
    func afterDelay() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        _ = c.send(.hotkeyPressed(.allWindows))
        #expect(c.send(.activationDelayElapsed) == [])
        #expect(c.send(.modifierReleased) == [.activate(2)])
    }

    @Test("El Recency Order sigue los cambios de foco externos")
    func externalFocus() {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        _ = c.send(.windowFocused(3))
        _ = c.send(.hotkeyPressed(.allWindows))
        #expect(c.send(.modifierReleased) == [.cancelActivationTimer, .activate(1)])
    }

    @Test("Las Windows que no vio recibir foco van al final, en orden de apilamiento")
    func unknownAtEnd() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        _ = c.send(.windowFocused(2))
        // Aparecen 4 (apilada detrás) y 3 (apilada delante): quedan después de 2 y 1.
        _ = c.send(.snapshot(Snapshot(windows: [win(1, stack: 2), win(2, stack: 3), win(3, stack: 0), win(4, stack: 1)])))
        // Orden esperado: 2, 1, 3, 4. Se activa 1, 3 y luego 4 yendo a foco.
        _ = c.send(.windowFocused(1))
        _ = c.send(.hotkeyPressed(.allWindows))
        #expect(c.send(.modifierReleased) == [.cancelActivationTimer, .activate(2)])
        _ = c.send(.windowFocused(2))
        _ = c.send(.windowFocused(4))
        _ = c.send(.windowFocused(3))
        _ = c.send(.hotkeyPressed(.allWindows))
        #expect(c.send(.modifierReleased) == [.cancelActivationTimer, .activate(4)])
    }

    @Test("Una Window desconocida nunca pasa delante de las que recibieron foco")
    func unknownBehindFocused() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        _ = c.send(.windowFocused(2))
        _ = c.send(.snapshot(Snapshot(windows: [win(1, stack: 1), win(2, stack: 2), win(3, stack: 0)])))
        // Recency: 2, 1, 3. Segunda = 1.
        _ = c.send(.hotkeyPressed(.allWindows))
        #expect(c.send(.modifierReleased) == [.cancelActivationTimer, .activate(1)])
    }

    @Test("Sin foco previo, el orden inicial es el de apilamiento")
    func initialStacking() {
        var c = core([win(7, stack: 1), win(5, stack: 0), win(9, stack: 2)])
        _ = c.send(.hotkeyPressed(.allWindows))
        #expect(c.send(.modifierReleased) == [.cancelActivationTimer, .activate(7)])
    }

    @Test("Las Windows cerradas salen del Recency Order")
    func closed() {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        _ = c.send(.snapshot(Snapshot(windows: [win(1, stack: 0), win(3, stack: 1)])))
        _ = c.send(.hotkeyPressed(.allWindows))
        #expect(c.send(.modifierReleased) == [.cancelActivationTimer, .activate(3)])
    }

    @Test("Con una sola Window, el Quick Switch no activa nada")
    func single() {
        var c = core([win(1, stack: 0)])
        _ = c.send(.hotkeyPressed(.allWindows))
        #expect(c.send(.modifierReleased) == [.cancelActivationTimer])
    }

    @Test("Sin Windows no se inicia ninguna Switch Session")
    func none() {
        var c = core([])
        #expect(c.send(.hotkeyPressed(.allWindows)) == [])
        #expect(c.send(.modifierReleased) == [])
    }

    @Test("Con el Scope desactivado el evento pasa al sistema")
    func disabled() {
        var c = core([win(1, stack: 0), win(2, stack: 1)], config: .init(allWindowsEnabled: false))
        #expect(c.send(.hotkeyPressed(.allWindows)) == [.passEventToSystem])
        #expect(c.send(.modifierReleased) == [])
    }

    @Test("Current App solo considera las Windows de la App con foco")
    func currentApp() {
        var c = core([win(1, app: 1, stack: 0), win(2, app: 2, stack: 1), win(3, app: 1, stack: 2)])
        _ = c.send(.hotkeyPressed(.currentApp))
        #expect(c.send(.modifierReleased) == [.cancelActivationTimer, .activate(3)])
    }
}
