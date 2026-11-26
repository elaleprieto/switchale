import Testing
import SwitchaleCore

@Suite("Varias pantallas")
struct MultiScreenTests {
    private let windows = [
        win(1, stack: 0),
        win(2, stack: 1, screen: otherScreen),
        win(3, stack: 2),
    ]

    @Test("Por defecto las Windows de otras pantallas entran en el Window Switcher")
    func includesOtherScreensByDefault() {
        var c = core(windows)
        let content = shownContent(holdHotkey(&c))
        #expect(content?.items.map(\.id) == [.window(WindowID(1)), .window(WindowID(2)), .window(WindowID(3))])
    }

    @Test("Con la inclusión desactivada solo aparecen las Windows de la pantalla actual")
    func excludesOtherScreensWhenDisabled() {
        var c = core(windows, config: .init(includesOtherScreens: false))
        let content = shownContent(holdHotkey(&c))
        #expect(content?.items.map(\.id) == [.window(WindowID(1)), .window(WindowID(3))])
    }

    @Test("Un Quick Switch puede activar una Window de otra pantalla")
    func activatesWindowOnOtherScreen() {
        var c = core([win(1, stack: 0), win(2, stack: 1, screen: otherScreen)])
        #expect(quickSwitchTarget(&c) == WindowID(2))
    }

    @Test("Cambiar la configuración a excluir otras pantallas se aplica a la siguiente Switch Session")
    func configChangeApplies() {
        var c = core(windows)
        _ = c.send(.configChanged(.init(includesOtherScreens: false)))
        #expect(shownContent(holdHotkey(&c))?.items.count == 2)
    }

    @Test("El panel aparece en la pantalla de la Window con foco según la foto, no según Recency Order")
    func panelOnFocusedWindowScreen() {
        var c = SwitcherCore()
        _ = c.send(.snapshot(snapshot(windows, focused: 2)))
        _ = c.send(.windowFocused(WindowID(1)))
        #expect(shownContent(holdHotkey(&c))?.screen == otherScreen)
    }

    @Test("Sin Window con foco, el panel aparece en la pantalla del mouse")
    func panelFallsBackToMouseScreen() {
        var c = SwitcherCore()
        _ = c.send(.snapshot(snapshot(windows, focused: nil, mouse: otherScreen)))
        #expect(shownContent(holdHotkey(&c))?.screen == otherScreen)
    }

    @Test("Si la Window con foco no está en la foto, el panel aparece en la pantalla del mouse")
    func unknownFocusedWindowFallsBackToMouseScreen() {
        var c = SwitcherCore()
        _ = c.send(.snapshot(snapshot(windows, focused: 99, mouse: otherScreen)))
        #expect(shownContent(holdHotkey(&c))?.screen == otherScreen)
    }

    @Test("La pantalla actual es la de la Window con foco: sin otras pantallas, solo aparecen sus Windows")
    func currentScreenIsFocusedWindowScreen() {
        var c = SwitcherCore(config: .init(includesOtherScreens: false))
        _ = c.send(.snapshot(snapshot(windows, focused: 2)))
        #expect(shownContent(holdHotkey(&c))?.items.map(\.id) == [.window(WindowID(2))])
    }

    @Test("Sin Window con foco, la pantalla actual es la del mouse")
    func currentScreenFallsBackToMouse() {
        var c = SwitcherCore(config: .init(includesOtherScreens: false))
        _ = c.send(.snapshot(snapshot(windows, mouse: otherScreen)))
        #expect(shownContent(holdHotkey(&c))?.items.map(\.id) == [.window(WindowID(2))])
    }

    @Test("Con la opción pantalla del mouse, el panel aparece donde está el mouse")
    func panelOnMouseScreen() {
        var c = SwitcherCore(config: .init(panelScreen: .mouse))
        _ = c.send(.snapshot(snapshot(windows, focused: 1, mouse: otherScreen)))
        #expect(shownContent(holdHotkey(&c))?.screen == otherScreen)
    }

    @Test("Con la opción pantalla principal, el panel aparece en la principal")
    func panelOnPrimaryScreen() {
        var c = SwitcherCore(config: .init(panelScreen: .primary))
        _ = c.send(.snapshot(snapshot(windows, focused: 1, primary: otherScreen)))
        #expect(shownContent(holdHotkey(&c))?.screen == otherScreen)
    }

    @Test("La pantalla del panel no cambia en los refrescos de la foto con el panel abierto")
    func panelScreenIsFixedForTheSession() {
        var c = SwitcherCore()
        _ = c.send(.snapshot(snapshot(windows, focused: 1)))
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        _ = c.send(.snapshot(snapshot(windows, focused: 1)))
        #expect(shownContent(c.send(.activationDelayElapsed))?.screen == mainScreen)

        // El foco pasa a otra pantalla con el panel abierto: el panel se queda donde estaba.
        let effects = c.send(.snapshot(snapshot(windows, focused: 2, mouse: otherScreen)))
        for case .updateSwitcher(let content) in effects { #expect(content.screen == mainScreen) }
        #expect(shownContent(effects) == nil)
    }

    @Test("Si la foto de la Switch Session no llegó al vencer el Activation Delay, el panel aparece igual")
    func panelDoesNotWaitForFreshSnapshot() {
        var c = SwitcherCore()
        _ = c.send(.snapshot(snapshot(windows, focused: 1)))
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        #expect(shownContent(c.send(.activationDelayElapsed))?.screen == mainScreen)
    }

    @Test("Sin la foto de la Switch Session, la pantalla sale de la Window con foco según los cambios de foco")
    func provisionalScreenFollowsFocusEvents() {
        var c = SwitcherCore()
        _ = c.send(.snapshot(snapshot(windows, focused: 1)))  // foto vieja: foco en la principal
        _ = c.send(.windowFocused(WindowID(2)))  // después el foco pasó a la otra pantalla
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        #expect(shownContent(c.send(.activationDelayElapsed))?.screen == otherScreen)
    }

    @Test("Sin la foto de la Switch Session y sin Window con foco, el panel aparece en la pantalla del mouse")
    func provisionalScreenWithoutFocusedWindow() {
        var c = SwitcherCore()
        _ = c.send(.snapshot(snapshot(windows, focused: 1, mouse: otherScreen)))
        _ = c.send(.windowFocused(WindowID(1)))
        _ = c.send(.appActivated(AppID(2)))  // una App sin Window con foco (p. ej. el escritorio)
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        #expect(shownContent(c.send(.activationDelayElapsed))?.screen == otherScreen)
    }

    @Test("La foto de la Switch Session corrige la pantalla del panel que apareció sin ella")
    func freshSnapshotCorrectsProvisionalScreen() {
        var c = SwitcherCore()
        _ = c.send(.snapshot(snapshot(windows, focused: 2)))  // foto vieja: foco en otra pantalla
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        #expect(shownContent(c.send(.activationDelayElapsed))?.screen == otherScreen)

        let fresh = c.send(.snapshot(snapshot(windows, focused: 1)))
        #expect(fresh.contains { if case .updateSwitcher(let content) = $0 { content.screen == mainScreen } else { false } })

        // Corregida una vez, queda fija hasta que termine la Switch Session.
        let later = c.send(.snapshot(snapshot(windows, focused: 2)))
        for case .updateSwitcher(let content) in later { #expect(content.screen == mainScreen) }
    }

    @Test("La pantalla del panel se decide de nuevo en cada Switch Session")
    func panelScreenIsDecidedPerSession() {
        var c = SwitcherCore()
        _ = c.send(.snapshot(snapshot(windows, focused: 1)))
        #expect(shownContent(holdHotkey(&c))?.screen == mainScreen)
        _ = c.send(.modifiersChanged([]))
        _ = c.send(.keyUp(.tab))
        _ = c.send(.snapshot(snapshot(windows, focused: 2)))
        #expect(shownContent(holdHotkey(&c))?.screen == otherScreen)
    }
}
