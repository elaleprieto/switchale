import AppKit
import SwitchaleCore

/// Ventana de Preferencias: pestañas General y Appearance y el botón "Restaurar valores por
/// defecto". Cada control escribe en `UserDefaults` apenas cambia (`SwitcherPreferences` y
/// `LoginItem`); el Orchestrator lo aplica sin reiniciar.
@MainActor
final class PreferencesWindowController: NSWindowController {
    private struct ScopeControls {
        let enabled: NSButton
        let modifier: NSPopUpButton
        let key: NSPopUpButton
    }

    private var scopeControls: [Scope: ScopeControls] = [:]
    private let activationDelaySlider = NSSlider()
    private let activationDelayLabel = NSTextField(labelWithString: "")
    private let panelScreenPopUp = NSPopUpButton()
    private let includesMinimized = NSButton(checkboxWithTitle: "Minimized Windows", target: nil, action: nil)
    private let includesHiddenApps = NSButton(checkboxWithTitle: "Windows de Hidden Apps", target: nil, action: nil)
    private let includesOtherScreens = NSButton(checkboxWithTitle: "Windows de otras pantallas", target: nil, action: nil)
    private let launchAtLogin = NSButton(checkboxWithTitle: "Iniciar switchale al loguearse", target: nil, action: nil)
    private let launchAtLoginNote = NSTextField(labelWithString: "Falta aprobarlo en Configuración del Sistema › General › Ítems de inicio")
    private let thumbnailSlider = NSSlider()

    private static let panelScreens: [(PanelScreen, String)] = [
        (.focusedWindow, "La de la Window con foco"), (.mouse, "La del mouse"), (.primary, "La principal"),
    ]

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.title = "Preferencias de switchale"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let tabs = NSTabView()
        tabs.addTabViewItem(tab("General", makeGeneral()))
        tabs.addTabViewItem(tab("Appearance", makeAppearance()))

        let restore = NSButton(title: "Restaurar valores por defecto", target: self, action: #selector(restoreDefaults))

        let stack = NSStackView(views: [tabs, restore])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        tabs.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            tabs.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 20),
            tabs.widthAnchor.constraint(equalToConstant: 520),
        ])
        window.contentView = content
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    /// Muestra los valores guardados y trae la ventana al frente (la app no tiene ícono en el Dock).
    func present() {
        render(SwitcherPreferences.load(), loginItem: LoginItem.status())
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Pestañas

    private func tab(_ label: String, _ view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: label)
        item.label = label
        let container = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            view.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            view.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -20),
        ])
        item.view = container
        return item
    }

    private func makeGeneral() -> NSView {
        var rows: [[NSView]] = []
        for scope in Scope.allCases {
            let controls = ScopeControls(
                enabled: NSButton(checkboxWithTitle: "Activado", target: self, action: #selector(changed)),
                modifier: popUp(HotkeyModifier.allCases.map(\.title)),
                key: popUp(HotkeyKey.allCases.map(\.title))
            )
            scopeControls[scope] = controls
            let hotkey = NSStackView(views: [controls.enabled, controls.modifier, controls.key])
            hotkey.spacing = 8
            rows.append([label(scope.title), hotkey])
        }

        activationDelaySlider.minValue = Double(ActivationDelay.range.lowerBound)
        activationDelaySlider.maxValue = Double(ActivationDelay.range.upperBound)
        activationDelaySlider.isContinuous = true
        activationDelaySlider.target = self
        activationDelaySlider.action = #selector(changed)
        activationDelaySlider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        activationDelayLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let delay = NSStackView(views: [activationDelaySlider, activationDelayLabel])
        delay.spacing = 8
        rows.append([label("Activation Delay"), delay])

        Self.panelScreens.forEach { panelScreenPopUp.addItem(withTitle: $0.1) }
        panelScreenPopUp.target = self
        panelScreenPopUp.action = #selector(changed)
        rows.append([label("Pantalla del panel"), panelScreenPopUp])

        for checkbox in [includesMinimized, includesHiddenApps, includesOtherScreens] {
            checkbox.target = self
            checkbox.action = #selector(changed)
        }
        rows.append([label("Incluir"), includesMinimized])
        rows.append([NSGridCell.emptyContentView, includesHiddenApps])
        rows.append([NSGridCell.emptyContentView, includesOtherScreens])

        launchAtLogin.target = self
        launchAtLogin.action = #selector(launchAtLoginChanged)
        rows.append([label("Inicio"), launchAtLogin])
        launchAtLoginNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        launchAtLoginNote.textColor = .secondaryLabelColor
        rows.append([NSGridCell.emptyContentView, launchAtLoginNote])

        return grid(rows)
    }

    private func makeAppearance() -> NSView {
        let range = ThumbnailSize.widthRange
        thumbnailSlider.minValue = Double(range.lowerBound)
        thumbnailSlider.maxValue = Double(range.upperBound)
        thumbnailSlider.numberOfTickMarks = (range.upperBound - range.lowerBound) / ThumbnailSize.widthStep + 1
        thumbnailSlider.allowsTickMarkValuesOnly = true
        thumbnailSlider.isContinuous = true
        thumbnailSlider.target = self
        thumbnailSlider.action = #selector(changed)
        thumbnailSlider.widthAnchor.constraint(equalToConstant: 240).isActive = true
        let slider = NSStackView(views: [NSTextField(labelWithString: "Chico"), thumbnailSlider, NSTextField(labelWithString: "Grande")])
        slider.spacing = 8
        return grid([[label("Tamaño de Thumbnail"), slider]])
    }

    private func grid(_ rows: [[NSView]]) -> NSGridView {
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        return grid
    }

    private func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text + ":")
    }

    private func popUp(_ titles: [String]) -> NSPopUpButton {
        let popUp = NSPopUpButton()
        // Las opciones que repetirían el Hotkey del otro Scope se deshabilitan en `render`.
        popUp.autoenablesItems = false
        popUp.addItems(withTitles: titles)
        popUp.target = self
        popUp.action = #selector(changed)
        return popUp
    }

    // MARK: - Valores

    /// Pone los controles en estos valores y el login item en su estado real.
    private func render(_ config: SwitcherConfig, loginItem: LoginItemStatus) {
        for scope in Scope.allCases {
            guard let controls = scopeControls[scope] else { continue }
            let hotkey = config.hotkeys[scope]
            controls.enabled.state = config.enabledScopes.contains(scope) ? .on : .off
            controls.modifier.selectItem(at: HotkeyModifier.allCases.firstIndex(of: hotkey.modifier) ?? 0)
            controls.key.selectItem(at: HotkeyKey.allCases.firstIndex(of: hotkey.key) ?? 0)
            // Un Hotkey ya usado por el otro Scope no se puede elegir (aunque ese Scope esté
            // desactivado). El Hotkey de un Scope desactivado se puede cambiar: vale al activarlo.
            for (index, modifier) in HotkeyModifier.allCases.enumerated() {
                controls.modifier.item(at: index)?.isEnabled =
                    config.isHotkeyAvailable(Hotkey(modifier: modifier, key: hotkey.key), for: scope)
            }
            for (index, key) in HotkeyKey.allCases.enumerated() {
                controls.key.item(at: index)?.isEnabled =
                    config.isHotkeyAvailable(Hotkey(modifier: hotkey.modifier, key: key), for: scope)
            }
        }
        activationDelaySlider.integerValue = config.activationDelay.milliseconds
        activationDelayLabel.stringValue = "\(config.activationDelay.milliseconds) ms"
        panelScreenPopUp.selectItem(at: Self.panelScreens.firstIndex { $0.0 == config.panelScreen } ?? 0)
        includesMinimized.state = config.includesMinimizedWindows ? .on : .off
        includesHiddenApps.state = config.includesHiddenApps ? .on : .off
        includesOtherScreens.state = config.includesOtherScreens ? .on : .off
        launchAtLogin.state = loginItem.isRegistered ? .on : .off
        launchAtLoginNote.isHidden = loginItem != .requiresApproval
        thumbnailSlider.integerValue = config.thumbnailSize.width
    }

    /// La configuración que muestran los controles.
    private func configFromControls() -> SwitcherConfig {
        var config = SwitcherConfig()
        for scope in Scope.allCases {
            guard let controls = scopeControls[scope] else { continue }
            if controls.enabled.state == .off { config.enabledScopes.remove(scope) }
            let modifier = HotkeyModifier.allCases[max(0, controls.modifier.indexOfSelectedItem)]
            let key = HotkeyKey.allCases[max(0, controls.key.indexOfSelectedItem)]
            config.hotkeys[scope] = Hotkey(modifier: modifier, key: key)
        }
        config.activationDelay = ActivationDelay(milliseconds: Int(activationDelaySlider.doubleValue.rounded()))
        config.panelScreen = Self.panelScreens[max(0, panelScreenPopUp.indexOfSelectedItem)].0
        config.includesMinimizedWindows = includesMinimized.state == .on
        config.includesHiddenApps = includesHiddenApps.state == .on
        config.includesOtherScreens = includesOtherScreens.state == .on
        config.thumbnailSize = ThumbnailSize(width: thumbnailSlider.integerValue)
        return config
    }

    // MARK: - Acciones

    @objc private func changed() {
        let config = configFromControls()
        SwitcherPreferences.save(config)
        render(config, loginItem: LoginItem.status())
    }

    /// Después de registrar o quitar el login item, el checkbox muestra lo que quedó en macOS.
    @objc private func launchAtLoginChanged() {
        LoginItem.setWanted(launchAtLogin.state == .on)
        render(SwitcherPreferences.load(), loginItem: LoginItem.status())
    }

    @objc private func restoreDefaults() {
        SwitcherPreferences.restoreDefaults()
        LoginItem.restoreDefault()
        render(SwitcherPreferences.load(), loginItem: LoginItem.status())
    }
}

// MARK: - Títulos

private extension Scope {
    var title: String {
        switch self {
        case .allWindows: "All Windows"
        case .currentApp: "Current App"
        }
    }
}

private extension HotkeyModifier {
    var title: String {
        switch self {
        case .command: "⌘ Command"
        case .option: "⌥ Option"
        case .control: "⌃ Control"
        case .shift: "⇧ Shift"
        }
    }
}

private extension HotkeyKey {
    var title: String {
        switch self {
        case .tab: "⇥ Tab"
        case .grave: "` Acento grave"
        }
    }
}
