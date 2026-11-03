import AppKit
import SwitchaleCore

/// Ventana de permisos: una fila por permiso con su estado, una aclaración de qué
/// pasa sin él y un botón que abre el panel de Configuración del Sistema.
@MainActor
final class PermissionsWindowController: NSWindowController {
    private let onRequest: (Permission) -> Void
    private let stack = NSStackView()

    init(onRequest: @escaping (Permission) -> Void) {
        self.onRequest = onRequest
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.title = "Permisos de switchale"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: 480),
        ])
        window.contentView = content
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    /// Trae la ventana al frente (la app no tiene ícono en el Dock).
    func present() {
        window?.center()
        showWindow(nil)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Redibuja las filas según el estado actual de los permisos.
    func update(_ guide: PermissionsGuide) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let intro = NSTextField(wrappingLabelWithString:
            "switchale necesita estos permisos para reemplazar ⌘⇥. La ventana se actualiza sola al otorgarlos.")
        intro.preferredMaxLayoutWidth = 440
        stack.addArrangedSubview(intro)

        for row in guide.rows {
            stack.addArrangedSubview(makeRow(row))
        }
        window?.layoutIfNeeded()
    }

    private func makeRow(_ row: PermissionRow) -> NSView {
        let symbol = row.isGranted ? "checkmark.circle.fill" : "exclamationmark.circle"
        let icon = NSImageView(image: NSImage(
            systemSymbolName: symbol, accessibilityDescription: row.statusText) ?? NSImage())
        icon.contentTintColor = row.isGranted ? .systemGreen : .systemOrange

        let title = NSTextField(labelWithString: row.title)
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let status = NSTextField(labelWithString: row.statusText)
        status.textColor = .secondaryLabelColor

        let header = NSStackView(views: [icon, title, status])
        header.spacing = 6

        let column = NSStackView(views: [header])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6

        if let note = row.note {
            let label = NSTextField(wrappingLabelWithString: note)
            label.preferredMaxLayoutWidth = 440
            label.textColor = .secondaryLabelColor
            column.addArrangedSubview(label)
        }
        if !row.isGranted {
            let button = PermissionButton(
                title: "Abrir Configuración del Sistema…",
                target: self,
                action: #selector(openSettings(_:))
            )
            button.permission = row.permission
            column.addArrangedSubview(button)
        }
        return column
    }

    @objc private func openSettings(_ sender: PermissionButton) {
        guard let permission = sender.permission else { return }
        onRequest(permission)
    }
}

/// Botón que recuerda a qué permiso corresponde.
private final class PermissionButton: NSButton {
    var permission: Permission?
}
