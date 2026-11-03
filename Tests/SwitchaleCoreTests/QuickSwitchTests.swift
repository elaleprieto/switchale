import Testing
@testable import SwitchaleCore

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
        var c = core([win(1, stack: 0)], config: .init(activationDelay: ActivationDelay(milliseconds: 150)))
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
        deliverFreshSnapshot(&c)
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
        var c = core([win(1, stack: 0), win(2, stack: 1)], config: .init(enabledScopes: [.currentApp]))
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
    @Test("Se excluyen las de otros Spaces, y con las dos inclusiones desactivadas también las Minimized y las de Hidden Apps")
    func exclusions() {
        var c = core([
            win(1, stack: 0),
            win(2, stack: 1, minimized: true),
            win(3, stack: 2, appHidden: true),
            win(4, stack: 3, inSpace: false),
            win(6, stack: 5),
        ], config: visibleOnly)
        #expect(quickSwitchTarget(&c) == WindowID(6))
    }

    @Test("Si solo queda una Window elegible, no se activa nada")
    func onlyOneEligible() {
        var c = core([win(1, stack: 0), win(2, stack: 1, minimized: true)], config: visibleOnly)
        #expect(quickSwitchTarget(&c) == nil)
    }

    @Test("Una Window que sale de Minimized vuelve a entrar sin perder su lugar de Recency Order")
    func unminimizedReturns() {
        var c = core([win(1, stack: 0), win(2, stack: 1, minimized: true), win(3, stack: 2)], config: visibleOnly)
        #expect(quickSwitchTarget(&c) == WindowID(3))
        _ = c.send(.snapshot(snapshot([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])))
        #expect(quickSwitchTarget(&c) == WindowID(2))
    }
}

@Suite("Minimized Windows y Hidden Apps")
struct MinimizedAndHiddenInclusionTests {
    private let windows = [win(1, stack: 0), win(2, stack: 1, minimized: true), win(3, stack: 2, appHidden: true)]

    private func shownItems(_ config: SwitcherConfig) -> [SwitcherItem] {
        var c = core(windows, config: config)
        guard case .showSwitcher(let content)? = holdHotkey(&c).first else { Issue.record("sin Switcher"); return [] }
        return content.items
    }

    @Test("Por defecto las Minimized y las de Hidden Apps entran, y el ítem las marca")
    func includedByDefault() {
        let items = shownItems(.init())
        #expect(items.map(\.id) == [.window(WindowID(1)), .window(WindowID(2)), .window(WindowID(3))])
        #expect(items.map(\.mark) == [.none, .minimized, .appHidden])
    }

    @Test("Una Window minimizada de una App oculta se marca como minimizada")
    func minimizedWinsOverAppHidden() {
        var c = core([win(1, stack: 0), win(2, stack: 1, minimized: true, appHidden: true)])
        guard case .showSwitcher(let content)? = holdHotkey(&c).first else { Issue.record("sin Switcher"); return }
        #expect(content.items.map(\.mark) == [.none, .minimized])
    }

    @Test("Con las Minimized desactivadas no aparecen, pero las de Hidden Apps sí")
    func minimizedOff() {
        #expect(shownItems(.init(includesMinimizedWindows: false)).map(\.id) == [.window(WindowID(1)), .window(WindowID(3))])
    }

    @Test("Con las Hidden Apps desactivadas no aparecen, pero las Minimized sí")
    func hiddenOff() {
        #expect(shownItems(.init(includesHiddenApps: false)).map(\.id) == [.window(WindowID(1)), .window(WindowID(2))])
    }
}
