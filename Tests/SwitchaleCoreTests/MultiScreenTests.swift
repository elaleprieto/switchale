import Testing
import SwitchaleCore

private func shownContent(_ effects: [SwitcherEffect]) -> SwitcherContent? {
    for case .showSwitcher(let content) in effects { return content }
    return nil
}

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
        #expect(content?.items.map(\.windowID) == [WindowID(1), WindowID(2), WindowID(3)])
    }

    @Test("Con la inclusión desactivada solo aparecen las Windows de la pantalla actual")
    func excludesOtherScreensWhenDisabled() {
        var c = core(windows, config: .init(includeOtherScreens: false))
        let content = shownContent(holdHotkey(&c))
        #expect(content?.items.map(\.windowID) == [WindowID(1), WindowID(3)])
    }

    @Test("Un Quick Switch puede activar una Window de otra pantalla")
    func activatesWindowOnOtherScreen() {
        var c = core([win(1, stack: 0), win(2, stack: 1, screen: otherScreen)])
        #expect(quickSwitchTarget(&c) == WindowID(2))
    }

    @Test("Cambiar la configuración a excluir otras pantallas se aplica a la siguiente Switch Session")
    func configChangeApplies() {
        var c = core(windows)
        _ = c.send(.configChanged(.init(includeOtherScreens: false)))
        #expect(shownContent(holdHotkey(&c))?.items.count == 2)
    }

    @Test("El panel aparece en la pantalla de la Window con foco")
    func panelOnFocusedWindowScreen() {
        var c = core(windows)
        _ = c.send(.windowFocused(WindowID(2)))
        #expect(shownContent(holdHotkey(&c))?.screen == otherScreen)
    }

    @Test("Si la Window con foco no está en la foto, el panel aparece en la pantalla actual")
    func panelFallsBackToCurrentScreen() {
        var c = core(windows)
        _ = c.send(.windowFocused(WindowID(99)))
        #expect(shownContent(holdHotkey(&c))?.screen == mainScreen)
    }

    @Test("Con la opción pantalla del mouse, el panel aparece donde está el mouse")
    func panelOnMouseScreen() {
        var c = SwitcherCore(config: .init(panelScreen: .mouse))
        _ = c.send(.snapshot(snapshot(windows, mouse: otherScreen)))
        #expect(shownContent(holdHotkey(&c))?.screen == otherScreen)
    }

    @Test("Con la opción pantalla principal, el panel aparece en la principal")
    func panelOnPrimaryScreen() {
        var c = SwitcherCore(config: .init(panelScreen: .primary))
        _ = c.send(.snapshot(snapshot(windows, primary: otherScreen)))
        #expect(shownContent(holdHotkey(&c))?.screen == otherScreen)
    }
}
