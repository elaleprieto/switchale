import Testing
import SwitchaleCore

@Suite("Window Switcher: botón de cerrar")
struct CloseButtonTests {
    @Test("La ✕ de una Window la cierra y el Window Switcher sigue abierto")
    func closesWindow() {
        var c = gridSession(3, columns: 3, selected: 1)
        #expect(c.send(.closeClicked(.window(WindowID(3)))) == [.closeWindow(WindowID(3))])
        // La Switch Session sigue: soltar el modificador activa la selección.
        #expect(c.send(.modifiersChanged([])) == [.hideSwitcher, .activate(WindowID(2))])
    }

    @Test("La ✕ de una Windowless App la cierra")
    func quitsWindowlessApp() {
        var c = core([win(1, stack: 0), win(2, stack: 1)], windowless: [8])
        holdHotkey(&c)
        #expect(c.send(.closeClicked(.windowlessApp(AppID(8)))) == [.quitApp(AppID(8))])
    }

    @Test("Cuando la foto ya no tiene la Window cerrada, sale del Window Switcher")
    func closedWindowLeaves() {
        var c = gridSession(3, columns: 3, selected: 1)
        _ = c.send(.closeClicked(.window(WindowID(3))))
        let effects = c.send(.snapshot(snapshot([win(1, stack: 0), win(2, stack: 1)])))
        #expect(effects == [.updateSwitcher(.init([item(1), item(2)], selected: 1, screen: mainScreen, thumbnailSize: ThumbnailSize()))])
    }

    @Test("Sin Window Switcher visible, la ✕ no hace nada")
    func withoutSwitcher() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        #expect(c.send(.closeClicked(.window(WindowID(2)))) == [])
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        #expect(c.send(.closeClicked(.window(WindowID(2)))) == [])
    }

    @Test("La ✕ de un ítem que ya no está en la Switch Session no hace nada")
    func unknownItem() {
        var c = gridSession(3, columns: 3, selected: 1)
        #expect(c.send(.closeClicked(.window(WindowID(9)))) == [])
    }
}
