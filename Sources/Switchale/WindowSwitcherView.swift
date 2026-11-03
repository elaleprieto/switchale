import AppKit
import SwitchaleCore

/// El Window Switcher en pantalla: un `NSPanel` no activante con fondo translúcido y una grilla
/// centrada que pasa a la siguiente fila cuando no entra. Solo dibuja lo que pide el núcleo;
/// el teclado lo recibe el event tap, así que el `NSPanel` nunca toma foco.
@MainActor
final class WindowSwitcherView {
    private let panel: NSPanel
    private let background = NSVisualEffectView()
    private var cells: [SwitcherCell] = []

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none

        // Material de HUD: sigue el modo claro u oscuro del sistema con desenfoque nativo.
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = Metrics.cornerRadius
        background.layer?.masksToBounds = true
        panel.contentView = background
    }

    func show(_ content: SwitcherContent) {
        layout(content)
        panel.orderFrontRegardless()
    }

    func update(_ content: SwitcherContent) {
        layout(content)
    }

    func select(_ index: Int) {
        for (offset, cell) in cells.enumerated() { cell.isSelected = offset == index }
    }

    func hide() {
        panel.orderOut(nil)
    }

    // MARK: - Grilla

    private func layout(_ content: SwitcherContent) {
        let items = content.items
        let screen = NSScreen.screens.first { $0.screenID == content.screen } ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let cell = Metrics.cellSize
        let available = visible.width * Metrics.maxWidthFraction - 2 * Metrics.padding
        let fitting = Int((available + Metrics.spacing) / (cell.width + Metrics.spacing))
        let columns = max(1, min(items.count, fitting))
        let rows = max(1, (items.count + columns - 1) / columns)

        let gridWidth = CGFloat(columns) * cell.width + CGFloat(columns - 1) * Metrics.spacing
        let gridHeight = CGFloat(rows) * cell.height + CGFloat(rows - 1) * Metrics.spacing
        let size = NSSize(width: gridWidth + 2 * Metrics.padding, height: gridHeight + 2 * Metrics.padding)

        cells.forEach { $0.removeFromSuperview() }
        cells = items.enumerated().map { index, item in
            let row = index / columns
            let column = index % columns
            // Cada fila se centra: la última, si está incompleta, queda en el medio.
            let inRow = min(columns, items.count - row * columns)
            let rowWidth = CGFloat(inRow) * cell.width + CGFloat(inRow - 1) * Metrics.spacing
            let x = (size.width - rowWidth) / 2 + CGFloat(column) * (cell.width + Metrics.spacing)
            let y = size.height - Metrics.padding - CGFloat(row + 1) * cell.height - CGFloat(row) * Metrics.spacing

            let view = SwitcherCell(frame: NSRect(origin: NSPoint(x: x, y: y), size: cell))
            view.configure(title: item.title, icon: Self.icon(for: item.appID))
            view.isSelected = index == content.selected
            background.addSubview(view)
            return view
        }

        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private static func icon(for app: AppID) -> NSImage? {
        NSRunningApplication(processIdentifier: pid_t(app.rawValue))?.icon
    }
}

/// Medidas del Window Switcher y de sus celdas, en puntos.
private enum Metrics {
    static let cellSize = NSSize(width: 132, height: 124)
    static let iconSize: CGFloat = 72
    static let spacing: CGFloat = 8
    static let padding: CGFloat = 20
    static let cornerRadius: CGFloat = 18
    /// Fracción del ancho de la pantalla que puede ocupar la grilla antes de pasar a otra fila.
    static let maxWidthFraction: CGFloat = 0.9

    static let cellCornerRadius: CGFloat = 12
    /// Margen interno de la celda alrededor del ícono y del título.
    static let cellInset: CGFloat = 8
    static let titleHeight: CGFloat = 18
    static let titleFontSize: CGFloat = 12
    /// Separación extra entre el borde inferior de la celda y el título.
    static let titleBottomOffset: CGFloat = 4
    static let selectionBorderWidth: CGFloat = 2
    static let selectionFillAlpha: CGFloat = 0.3
}

/// Una celda de la grilla: el ícono de la App y, debajo, el título de la Window.
private final class SwitcherCell: NSView {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    var isSelected = false {
        didSet { needsDisplay = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Metrics.cellCornerRadius
        layer?.borderWidth = Metrics.selectionBorderWidth

        let iconSize = Metrics.iconSize
        let inset = Metrics.cellInset
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.frame = NSRect(
            x: (frame.width - iconSize) / 2,
            y: frame.height - inset - iconSize,
            width: iconSize,
            height: iconSize
        )
        addSubview(iconView)

        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.font = .systemFont(ofSize: Metrics.titleFontSize, weight: .medium)
        label.textColor = .labelColor
        label.frame = NSRect(
            x: inset,
            y: inset + Metrics.titleBottomOffset,
            width: frame.width - 2 * inset,
            height: Metrics.titleHeight
        )
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    func configure(title: String, icon: NSImage?) {
        label.stringValue = title
        label.toolTip = title
        iconView.image = icon
    }

    override var wantsUpdateLayer: Bool { true }

    /// Los colores dinámicos se resuelven acá, con la apariencia vigente (modo claro u oscuro).
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = isSelected
                ? NSColor.controlAccentColor.withAlphaComponent(Metrics.selectionFillAlpha).cgColor
                : NSColor.clear.cgColor
            layer?.borderColor = isSelected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        }
    }
}
