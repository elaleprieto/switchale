import Testing
import SwitchaleCore

private func shownIDs(_ effects: [SwitcherEffect]) -> [ItemID]? {
    for case .showSwitcher(let content) in effects { return content.items.map(\.id) }
    return nil
}

@Suite("Windows de otros Spaces")
struct OtherSpacesTests {
    private let windows = [
        win(1, stack: 0),
        win(2, stack: 1, inSpace: false),
        win(3, stack: 2),
    ]

    @Test("Con la opción activada, las Windows de otros Spaces entran en el Window Switcher en Recency Order")
    func includesOtherSpacesWhenEnabled() {
        var c = core(windows, config: .init(includesOtherSpaces: true))
        #expect(shownIDs(holdHotkey(&c)) == [.window(WindowID(1)), .window(WindowID(2)), .window(WindowID(3))])
    }

    @Test("Por defecto la opción está desactivada y las Windows de otros Spaces no entran")
    func excludesOtherSpacesByDefault() {
        #expect(SwitcherConfig().includesOtherSpaces == false)
        var c = core(windows)
        #expect(shownIDs(holdHotkey(&c)) == [.window(WindowID(1)), .window(WindowID(3))])
    }

    @Test("Con la opción activada, un Quick Switch puede activar una Window de otro Space")
    func quickSwitchActivatesWindowInOtherSpace() {
        var c = core([win(1, stack: 0), win(2, stack: 1, inSpace: false)], config: .init(includesOtherSpaces: true))
        #expect(quickSwitchTarget(&c) == WindowID(2))
    }

    @Test("En Current App, con la opción activada entran las Windows de la App activa en otros Spaces, y no las de otras Apps")
    func currentAppIncludesItsWindowsInOtherSpaces() {
        var c = core([
            win(1, app: 1, stack: 0), win(2, app: 2, stack: 1, inSpace: false), win(3, app: 1, stack: 2, inSpace: false),
        ], config: .init(includesOtherSpaces: true), activeApp: 1)
        _ = c.send(.keyDown(.grave, [.option], isRepeat: false))
        deliverFreshSnapshot(&c)
        #expect(shownIDs(c.send(.activationDelayElapsed)) == [.window(WindowID(1)), .window(WindowID(3))])
    }

    @Test("Sin otras pantallas, las Windows de otros Spaces que están en otra pantalla siguen afuera")
    func otherScreensStillApplies() {
        var c = core([
            win(1, stack: 0), win(2, stack: 1, inSpace: false), win(3, stack: 2, screen: otherScreen, inSpace: false),
        ], config: .init(includesOtherScreens: false, includesOtherSpaces: true))
        #expect(shownIDs(holdHotkey(&c)) == [.window(WindowID(1)), .window(WindowID(2))])
    }

    @Test("Activar la opción se aplica a la siguiente Switch Session")
    func configChangeApplies() {
        var c = core(windows)
        _ = c.send(.configChanged(.init(includesOtherSpaces: true)))
        #expect(shownIDs(holdHotkey(&c))?.count == 3)
    }
}
