import Testing
import SwitchaleCore

/// La configuración por defecto con el Hotkey de un Scope cambiado.
private func config(_ scope: Scope, hotkey: Hotkey) -> SwitcherConfig {
    var config = SwitcherConfig()
    config.hotkeys[scope] = hotkey
    return config
}

@Suite("Configuración en vivo")
struct LiveConfigTests {
    let windows = [win(1, app: 1, stack: 0), win(2, app: 2, stack: 1), win(3, app: 1, stack: 2)]

    @Test("Cambiar el Hotkey de All Windows a ⌥⇥: la próxima Switch Session abre con ⌥⇥ y ⌘⇥ pasa al sistema")
    func changedHotkey() {
        var c = core(windows, activeApp: 1)
        _ = c.send(.configChanged(config(.allWindows, hotkey: Hotkey(modifier: .option, key: .tab))))
        #expect(c.send(.keyDown(.tab, [.command], isRepeat: false)) == [])
        #expect(c.send(.modifiersChanged([])) == [])
        #expect(c.send(.keyDown(.tab, [.option], isRepeat: false))
            == [.consumeEvent, .refreshSnapshot, .startActivationTimer(milliseconds: 80)])
        #expect(c.send(.modifiersChanged([.option])) == [])
        #expect(c.send(.modifiersChanged([])) == [.cancelActivationTimer, .activate(WindowID(2))])
    }

    @Test("Cambiar el Hotkey con una Switch Session abierta no la corta: sigue con el Hotkey con el que arrancó")
    func hotkeyChangeMidSession() {
        var c = core(windows)
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        _ = c.send(.configChanged(config(.allWindows, hotkey: Hotkey(modifier: .control, key: .grave))))
        #expect(c.send(.keyDown(.tab, [.command], isRepeat: false)) == [.consumeEvent])
        #expect(c.send(.modifiersChanged([])) == [.cancelActivationTimer, .activate(WindowID(3))])
        #expect(c.send(.keyDown(.grave, [.control], isRepeat: false))
            == [.consumeEvent, .refreshSnapshot, .startActivationTimer(milliseconds: 80)])
    }

    @Test("Un Hotkey con ` no retrocede con ⇧: ⌃⇧` pasa al sistema")
    func graveHotkeyDoesNotReverse() {
        var c = core(windows)
        _ = c.send(.configChanged(config(.allWindows, hotkey: Hotkey(modifier: .control, key: .grave))))
        #expect(c.send(.keyDown(.grave, [.control, .shift], isRepeat: false)) == [])
    }

    @Test("Un Hotkey con ⇥ retrocede con ⇧: ⌥⇧⇥ abre la Switch Session con la selección en el último ítem")
    func tabHotkeyReverses() {
        var c = core(windows)
        _ = c.send(.configChanged(config(.allWindows, hotkey: Hotkey(modifier: .option, key: .tab))))
        _ = c.send(.keyDown(.tab, [.option, .shift], isRepeat: false))
        #expect(c.send(.modifiersChanged([])) == [.cancelActivationTimer, .activate(WindowID(3))])
    }

    @Test("Desactivar un Scope en vivo: su Hotkey pasa al sistema desde la próxima Switch Session")
    func disableScopeLive() {
        var c = core(windows, activeApp: 1)
        #expect(quickSwitchTarget(&c) == WindowID(2))
        _ = c.send(.configChanged(.init(enabledScopes: [.currentApp])))
        #expect(c.send(.keyDown(.tab, [.command], isRepeat: false)) == [])
        #expect(c.send(.keyUp(.tab)) == [])
        #expect(c.send(.modifiersChanged([])) == [])
    }

    @Test("Cambiar el Activation Delay: la próxima Switch Session pide el temporizador con el valor nuevo")
    func activationDelayLive() {
        var c = core(windows)
        _ = c.send(.configChanged(.init(activationDelayMilliseconds: 200)))
        #expect(c.send(.keyDown(.tab, [.command], isRepeat: false))
            == [.consumeEvent, .refreshSnapshot, .startActivationTimer(milliseconds: 200)])
    }

    @Test("Desactivar en vivo la inclusión de Minimized Windows las saca de la próxima Switch Session")
    func inclusionLive() {
        var c = core([win(1, stack: 0), win(2, stack: 1, minimized: true), win(3, stack: 2)])
        #expect(shown(holdHotkey(&c))?.items.map(\.id) == [.window(WindowID(1)), .window(WindowID(2)), .window(WindowID(3))])
        _ = c.send(.modifiersChanged([]))
        _ = c.send(.windowFocused(WindowID(1)))
        _ = c.send(.configChanged(.init(includesMinimizedWindows: false)))
        #expect(shown(holdHotkey(&c))?.items.map(\.id) == [.window(WindowID(1)), .window(WindowID(3))])
    }

    @Test("Cambiar en vivo la pantalla del panel a la principal mueve el Window Switcher de la próxima Switch Session")
    func panelScreenLive() {
        var c = SwitcherCore()
        let windows = [win(1, stack: 0, screen: mainScreen), win(2, stack: 1, screen: mainScreen)]
        _ = c.send(.snapshot(snapshot(windows, focused: 1, primary: otherScreen)))
        _ = c.send(.configChanged(.init(panelScreen: .primary)))
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        _ = c.send(.snapshot(snapshot(windows, focused: 1, primary: otherScreen)))
        #expect(shown(c.send(.activationDelayElapsed))?.screen == otherScreen)
    }

    @Test("Volver a la configuración por defecto restaura ⌘⇥ y el Activation Delay de 80 ms")
    func restoreDefaults() {
        var c = core(windows)
        var custom = config(.allWindows, hotkey: Hotkey(modifier: .option, key: .tab))
        custom.activationDelayMilliseconds = 300
        _ = c.send(.configChanged(custom))
        _ = c.send(.configChanged(SwitcherConfig()))
        #expect(c.send(.keyDown(.tab, [.command], isRepeat: false))
            == [.consumeEvent, .refreshSnapshot, .startActivationTimer(milliseconds: 80)])
    }

    @Test("Cambiar el tamaño de Thumbnail con el Window Switcher abierto no cambia esa Switch Session; la próxima lo usa")
    func thumbnailSizeNextSession() {
        var c = core(windows)
        let bigger = ThumbnailSize(width: 224)
        #expect(shown(holdHotkey(&c))?.thumbnailSize == ThumbnailSize())
        var changed = SwitcherConfig()
        changed.thumbnailSize = bigger
        _ = c.send(.configChanged(changed))
        #expect(c.send(.snapshot(snapshot(windows))) == [])
        _ = c.send(.modifiersChanged([]))
        #expect(shown(holdHotkey(&c))?.thumbnailSize == bigger)
    }
}

@Suite("Tamaño de Thumbnail del slider")
struct ThumbnailSizeSliderTests {
    @Test("El slider fija el ancho y la altura sigue la proporción 16:10 del tamaño por defecto")
    func proportion() {
        #expect(ThumbnailSize(width: 160) == ThumbnailSize())
        #expect(ThumbnailSize(width: 224) == ThumbnailSize(width: 224, height: 140))
    }

    @Test("Un ancho fuera del rango del slider queda en el extremo más cercano")
    func clamps() {
        #expect(ThumbnailSize(width: 10) == ThumbnailSize(width: 96, height: 60))
        #expect(ThumbnailSize(width: 1000) == ThumbnailSize(width: 224, height: 140))
    }
}

private func shown(_ effects: [SwitcherEffect]) -> SwitcherContent? {
    for case .showSwitcher(let content) in effects { return content }
    return nil
}
