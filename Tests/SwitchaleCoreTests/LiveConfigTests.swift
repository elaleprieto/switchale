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

    @Test("Con ⇧⇥ como Hotkey, tocarlo y soltar ⇧ es un Quick Switch: activa la segunda Window, no la última")
    func shiftHotkeyQuickSwitch() {
        var c = core(windows)
        _ = c.send(.configChanged(config(.allWindows, hotkey: Hotkey(modifier: .shift, key: .tab))))
        #expect(c.send(.keyDown(.tab, [.shift], isRepeat: false))
            == [.consumeEvent, .refreshSnapshot, .startActivationTimer(milliseconds: 80)])
        #expect(c.send(.keyUp(.tab)) == [.consumeEvent])
        #expect(c.send(.modifiersChanged([])) == [.cancelActivationTimer, .activate(WindowID(2))])
    }

    @Test("Con ⇧⇥ como Hotkey, apretar ⇥ dentro de la Switch Session avanza la selección")
    func shiftHotkeyAdvances() {
        var c = core(windows)
        _ = c.send(.configChanged(config(.allWindows, hotkey: Hotkey(modifier: .shift, key: .tab))))
        _ = c.send(.keyDown(.tab, [.shift], isRepeat: false))
        deliverFreshSnapshot(&c)
        _ = c.send(.activationDelayElapsed)
        #expect(c.send(.keyDown(.tab, [.shift], isRepeat: false)) == [.consumeEvent, .selectItem(2)])
        #expect(c.send(.modifiersChanged([])) == [.hideSwitcher, .activate(WindowID(3))])
    }

    @Test("Con ⇧` como Hotkey de Current App, tocarlo y soltar ⇧ activa la segunda Window de la App activa")
    func shiftGraveHotkey() {
        var c = core(windows + [win(4, app: 1, stack: 3)], activeApp: 1)
        _ = c.send(.configChanged(config(.currentApp, hotkey: Hotkey(modifier: .shift, key: .grave))))
        _ = c.send(.keyDown(.grave, [.shift], isRepeat: false))
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
        _ = c.send(.configChanged(.init(activationDelay: ActivationDelay(milliseconds: 200))))
        #expect(c.send(.keyDown(.tab, [.command], isRepeat: false))
            == [.consumeEvent, .refreshSnapshot, .startActivationTimer(milliseconds: 200)])
    }

    @Test("Un Activation Delay fuera de rango queda en el extremo más cercano: entre 0 y 500 ms",
          arguments: [(-20, 0), (0, 0), (500, 500), (1000, 500)])
    func activationDelayClamps(configured: Int, expected: Int) {
        var c = core(windows)
        _ = c.send(.configChanged(.init(activationDelay: ActivationDelay(milliseconds: configured))))
        #expect(c.send(.keyDown(.tab, [.command], isRepeat: false))
            == [.consumeEvent, .refreshSnapshot, .startActivationTimer(milliseconds: expected)])
    }

    @Test("El Activation Delay va de a 10 ms: se redondea al más cercano",
          arguments: [(84, 80), (85, 90), (86, 90)])
    func activationDelaySteps(configured: Int, expected: Int) {
        var c = core(windows)
        _ = c.send(.configChanged(.init(activationDelay: ActivationDelay(milliseconds: configured))))
        #expect(c.send(.keyDown(.tab, [.command], isRepeat: false))
            == [.consumeEvent, .refreshSnapshot, .startActivationTimer(milliseconds: expected)])
    }

    @Test("Desactivar en vivo la inclusión de Minimized Windows las saca de la próxima Switch Session")
    func inclusionLive() {
        var c = core([win(1, stack: 0), win(2, stack: 1, minimized: true), win(3, stack: 2)])
        #expect(shownContent(holdHotkey(&c))?.items.map(\.id) == [.window(WindowID(1)), .window(WindowID(2)), .window(WindowID(3))])
        _ = c.send(.modifiersChanged([]))
        _ = c.send(.windowFocused(WindowID(1)))
        _ = c.send(.configChanged(.init(includesMinimizedWindows: false)))
        #expect(shownContent(holdHotkey(&c))?.items.map(\.id) == [.window(WindowID(1)), .window(WindowID(3))])
    }

    @Test("Cambiar en vivo la pantalla del panel a la principal mueve el Window Switcher de la próxima Switch Session")
    func panelScreenLive() {
        var c = SwitcherCore()
        let windows = [win(1, stack: 0, screen: mainScreen), win(2, stack: 1, screen: mainScreen)]
        _ = c.send(.snapshot(snapshot(windows, focused: 1, primary: otherScreen)))
        _ = c.send(.configChanged(.init(panelScreen: .primary)))
        _ = c.send(.keyDown(.tab, [.command], isRepeat: false))
        _ = c.send(.snapshot(snapshot(windows, focused: 1, primary: otherScreen)))
        #expect(shownContent(c.send(.activationDelayElapsed))?.screen == otherScreen)
    }

    @Test("Volver a la configuración por defecto restaura ⌘⇥ y el Activation Delay de 80 ms")
    func restoreDefaults() {
        var c = core(windows)
        var custom = config(.allWindows, hotkey: Hotkey(modifier: .option, key: .tab))
        custom.activationDelay = ActivationDelay(milliseconds: 300)
        _ = c.send(.configChanged(custom))
        _ = c.send(.configChanged(SwitcherConfig()))
        #expect(c.send(.keyDown(.tab, [.command], isRepeat: false))
            == [.consumeEvent, .refreshSnapshot, .startActivationTimer(milliseconds: 80)])
    }

    @Test("Cambiar el tamaño de Thumbnail con el Window Switcher abierto no cambia esa Switch Session; la próxima lo usa")
    func thumbnailSizeNextSession() {
        var c = core(windows)
        let bigger = ThumbnailSize(width: 224)
        #expect(shownContent(holdHotkey(&c))?.thumbnailSize == ThumbnailSize())
        var changed = SwitcherConfig()
        changed.thumbnailSize = bigger
        _ = c.send(.configChanged(changed))
        #expect(c.send(.snapshot(snapshot(windows))) == [])
        _ = c.send(.modifiersChanged([]))
        #expect(shownContent(holdHotkey(&c))?.thumbnailSize == bigger)
    }
}

@Suite("Tamaño de Thumbnail")
struct ThumbnailSizeTests {
    @Test("El Window Switcher muestra las Thumbnails del ancho configurado, con la proporción 16:10 del tamaño por defecto",
          arguments: [(160, 160, 100), (224, 224, 140), (96, 96, 60)])
    func proportion(width: Int, expectedWidth: Int, expectedHeight: Int) {
        #expect(shownThumbnailSize(width: width) == ThumbnailSize(width: expectedWidth, height: expectedHeight))
    }

    @Test("Un ancho fuera de rango queda en el extremo más cercano: entre 96 y 224 puntos",
          arguments: [(10, 96, 60), (1000, 224, 140)])
    func clamps(width: Int, expectedWidth: Int, expectedHeight: Int) {
        #expect(shownThumbnailSize(width: width) == ThumbnailSize(width: expectedWidth, height: expectedHeight))
    }

    @Test("El ancho va de a 16 puntos desde 96: se redondea al más cercano",
          arguments: [(170, 176, 110), (103, 96, 60), (105, 112, 70)])
    func steps(width: Int, expectedWidth: Int, expectedHeight: Int) {
        #expect(shownThumbnailSize(width: width) == ThumbnailSize(width: expectedWidth, height: expectedHeight))
    }

    /// El tamaño de Thumbnail con el que se muestra el Window Switcher con este ancho configurado.
    private func shownThumbnailSize(width: Int) -> ThumbnailSize? {
        var config = SwitcherConfig()
        config.thumbnailSize = ThumbnailSize(width: width)
        var c = core([win(1, stack: 0), win(2, stack: 1)], config: config)
        return shownContent(holdHotkey(&c))?.thumbnailSize
    }
}
