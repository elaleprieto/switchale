import Testing
import SwitchaleCore

@Suite("Quick Switch")
struct QuickSwitchTests {
    @Test("Tocar y soltar el Hotkey antes del Activation Delay activa la segunda Window, sin Window Switcher")
    func quickSwitch() {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        #expect(c.send(.keyDown(.tab, [.command], isRepeat: false))
            == [.consumeEvent, .refreshSnapshot, .startActivationTimer(milliseconds: 80)])
        #expect(c.send(.keyUp(.tab)) == [.consumeEvent])
        #expect(c.send(.modifiersChanged([])) == [.cancelActivationTimer, .activate(WindowID(2))])
    }

    @Test("El Activation Delay sale de la configuración del núcleo")
    func configurableDelay() {
        var c = core([win(1, stack: 0)], config: .init(activationDelayMilliseconds: 150))
        #expect(c.send(.keyDown(.tab, [.command], isRepeat: false)).contains(.startActivationTimer(milliseconds: 150)))
    }

    @Test("Quick Switch alterna entre las dos Windows más recientes, aun de la misma App")
    func toggles() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        #expect(quickSwitchTarget(&c) == WindowID(2))
        _ = c.send(.windowFocused(WindowID(2)))
        #expect(quickSwitchTarget(&c) == WindowID(1))
    }

    @Test("Si vence el Activation Delay, soltar oculta el Window Switcher, activa la segunda Window y no cancela el temporizador")
    func afterDelay() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        _ = c.send(.activationDelayElapsed)
        #expect(c.send(.modifiersChanged([])) == [.hideSwitcher, .activate(WindowID(2))])
    }

    @Test("Con una sola Window, el Quick Switch no activa nada")
    func single() {
        var c = core([win(1, stack: 0)])
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        #expect(c.send(.modifiersChanged([])) == [.cancelActivationTimer])
    }

    @Test("Sin Windows, soltar el modificador no activa nada")
    func none() {
        var c = core([])
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        #expect(c.send(.modifiersChanged([])) == [.cancelActivationTimer])
    }

    @Test("Con el Scope desactivado el evento pasa al sistema")
    func disabled() {
        var c = core([win(1, stack: 0), win(2, stack: 1)], config: .init(allWindowsEnabled: false))
        #expect(c.send(.keyDown(.tab, [.command], isRepeat: false)) == [])
        #expect(c.send(.keyUp(.tab)) == [])
        #expect(c.send(.modifiersChanged([])) == [])
    }

    @Test("⌘⇧⇥ también se consume, para que no abra el App Switcher nativo")
    func shiftTab() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        #expect(c.send(.keyDown(.tab, [.command, .shift], isRepeat: false)).contains(.consumeEvent))
    }

    @Test("Tocar y soltar ⌘⇧⇥ activa la última Window en Recency Order")
    func shiftTabQuickSwitch() {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        _ = c.send(.keyDown(.tab, [.command, .shift], isRepeat: false))
        _ = c.send(.keyUp(.tab))
        #expect(c.send(.modifiersChanged([])) == [.cancelActivationTimer, .activate(WindowID(3))])
    }

    @Test("Otras combinaciones con ⇥ pasan al sistema")
    func otherCombos() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        #expect(c.send(.keyDown(.tab, [], isRepeat: false)) == [])
        #expect(c.send(.keyDown(.tab, [.control], isRepeat: false)) == [])
        #expect(c.send(.keyDown(.tab, [.command, .option], isRepeat: false)) == [])
    }

    @Test("El autorepeat de ⌘⇥ se consume pero no abre otra sesión")
    func repeats() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        #expect(c.send(.keyDown(.tab, [.command], isRepeat: true)) == [.consumeEvent])
    }

    @Test("El keyUp de ⇥ se consume aunque el ⌘ ya se haya soltado")
    func keyUpAfterModifier() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        _ = c.send(.modifiersChanged([]))
        #expect(c.send(.keyUp(.tab)) == [.consumeEvent])
        #expect(c.send(.keyUp(.tab)) == [])
    }

    @Test("Un keyUp sin sesión previa pasa al sistema")
    func strayKeyUp() {
        var c = core([win(1, stack: 0)])
        #expect(c.send(.keyUp(.tab)) == [])
    }

    @Test("Si se pierde el soltado del modificador, la próxima lectura de modificadores cierra la sesión")
    func recoversFromLostRelease() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        #expect(c.send(.modifiersChanged([.shift])) == [.cancelActivationTimer, .activate(WindowID(2))])
        #expect(c.send(.modifiersChanged([])) == [])
    }

    @Test("Si la Window ya no existe al activarla, no se registra foco en ella y se pide una foto nueva")
    func activationFailed() {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        #expect(quickSwitchTarget(&c) == WindowID(2))
        #expect(c.send(.activationFailed(WindowID(2))) == [.refreshSnapshot])
        #expect(quickSwitchTarget(&c) == WindowID(2))
    }

    @Test("Mientras ⌘ sigue apretado la sesión sigue abierta")
    func modifierStillHeld() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        #expect(c.send(.modifiersChanged([.command, .shift])) == [])
    }
}

@Suite("Quick Switch: qué Windows entran")
struct QuickSwitchInclusionTests {
    @Test("Se excluyen las Minimized, las de Hidden Apps, las de otros Spaces y las de otras pantallas")
    func exclusions() {
        var c = core([
            win(1, stack: 0),
            win(2, stack: 1, minimized: true),
            win(3, stack: 2, appHidden: true),
            win(4, stack: 3, inSpace: false),
            win(5, stack: 4, screen: otherScreen),
            win(6, stack: 5),
        ])
        #expect(quickSwitchTarget(&c) == WindowID(6))
    }

    @Test("Si solo queda una Window elegible, no se activa nada")
    func onlyOneEligible() {
        var c = core([win(1, stack: 0), win(2, stack: 1, minimized: true)])
        #expect(quickSwitchTarget(&c) == nil)
    }

    @Test("Una Window que sale de Minimized vuelve a entrar sin perder su lugar de Recency Order")
    func unminimizedReturns() {
        var c = core([win(1, stack: 0), win(2, stack: 1, minimized: true), win(3, stack: 2)])
        #expect(quickSwitchTarget(&c) == WindowID(3))
        _ = c.send(.snapshot(snapshot([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])))
        #expect(quickSwitchTarget(&c) == WindowID(2))
    }
}
