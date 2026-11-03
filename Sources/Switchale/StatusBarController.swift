import AppKit

/// Ícono de switchale en la barra de menú y su menú ("Preferencias…" y "Salir").
@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = Self.makeIcon()
            button.toolTip = "switchale"
        }

        let menu = NSMenu()

        // Deshabilitado hasta que exista la ventana de Preferencias.
        let preferences = NSMenuItem(title: "Preferencias…", action: nil, keyEquivalent: ",")
        preferences.isEnabled = false
        menu.addItem(preferences)

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

    /// Ícono monocromo propio: un SF Symbol de ventanas apiladas, marcado como template
    /// para que macOS lo tiña según el modo claro u oscuro de la barra de menú.
    private static func makeIcon() -> NSImage? {
        let image = NSImage(
            systemSymbolName: "macwindow.on.rectangle",
            accessibilityDescription: "switchale"
        )
        image?.isTemplate = true
        return image
    }
}
