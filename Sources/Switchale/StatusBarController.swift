import AppKit
import SwitchaleCore

/// Ícono de switchale en la barra de menú y su menú: "Preferencias…" (deshabilitado
/// por ahora), "Permisos…" (abre la ventana de permisos) y "Salir". Si falta
/// Accesibilidad, el menú arranca con un aviso que también abre la ventana de permisos.
@MainActor
final class StatusBarController: NSObject {
    private static let appName = "switchale"

    private let statusItem: NSStatusItem
    private let onShowPermissions: () -> Void
    private let warningItem = NSMenuItem()
    private let warningSeparator = NSMenuItem.separator()

    init(onShowPermissions: @escaping () -> Void) {
        self.onShowPermissions = onShowPermissions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = Self.makeIcon()
            button.toolTip = Self.appName
        }

        let menu = NSMenu()

        warningItem.action = #selector(showPermissions)
        warningItem.target = self
        warningItem.image = NSImage(
            systemSymbolName: "exclamationmark.triangle",
            accessibilityDescription: nil
        )
        menu.addItem(warningItem)
        menu.addItem(warningSeparator)

        // Deshabilitado hasta que exista la ventana de Preferencias.
        let preferences = NSMenuItem(title: "Preferencias…", action: nil, keyEquivalent: ",")
        preferences.isEnabled = false
        menu.addItem(preferences)

        let permissions = NSMenuItem(
            title: "Permisos…",
            action: #selector(showPermissions),
            keyEquivalent: ""
        )
        permissions.target = self
        menu.addItem(permissions)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Salir",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)

        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    /// Muestra u oculta el aviso según el estado de los permisos.
    func update(_ guide: PermissionsGuide) {
        let warning = guide.menuWarning
        warningItem.title = (warning ?? "") + "…"
        warningItem.isHidden = warning == nil
        warningSeparator.isHidden = warning == nil
        statusItem.button?.toolTip = warning.map { "\(Self.appName): \($0)" } ?? Self.appName
    }

    @objc private func showPermissions() {
        onShowPermissions()
    }

    /// Ícono monocromo propio: un SF Symbol de ventanas apiladas, marcado como template
    /// para que macOS lo tiña según el modo claro u oscuro de la barra de menú.
    private static func makeIcon() -> NSImage? {
        let image = NSImage(
            systemSymbolName: "macwindow.on.rectangle",
            accessibilityDescription: appName
        )
        image?.isTemplate = true
        return image
    }
}
