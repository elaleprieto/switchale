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
    private var windowIDs: [WindowID] = []
    /// Tamaño de las Thumbnails, de la configuración.
    var thumbnailSize = ThumbnailSize() {
        didSet { cellSize = Metrics.cellSize(for: thumbnailSize) }
    }
    private var cellSize = Metrics.cellSize(for: ThumbnailSize())
    /// La Thumbnail ya capturada de una Window, si hay. Se consulta al armar la grilla, así un
    /// cambio de contenido no deja las celdas sin imagen.
    var thumbnailProvider: (WindowID) -> CGImage? = { _ in nil }

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

    /// Una Thumbnail nueva o refrescada: se cambia solo la imagen de esa celda.
    func thumbnailChanged(for window: WindowID) {
        guard let index = windowIDs.firstIndex(of: window) else { return }
        cells[index].thumbnail = thumbnailProvider(window)
    }

    /// Se descartaron las Thumbnails (p. ej. se perdió el permiso): las celdas vuelven a ícono y título.
    func thumbnailsDiscarded() {
        for cell in cells { cell.thumbnail = nil }
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
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let cell = cellSize
        let available = visible.width * Metrics.maxWidthFraction - 2 * Metrics.padding
        let fitting = Int((available + Metrics.spacing) / (cell.width + Metrics.spacing))
        let columns = max(1, min(items.count, fitting))
        let rows = max(1, (items.count + columns - 1) / columns)

        let gridWidth = CGFloat(columns) * cell.width + CGFloat(columns - 1) * Metrics.spacing
        let gridHeight = CGFloat(rows) * cell.height + CGFloat(rows - 1) * Metrics.spacing
        let size = NSSize(width: gridWidth + 2 * Metrics.padding, height: gridHeight + 2 * Metrics.padding)

        cells.forEach { $0.removeFromSuperview() }
        windowIDs = items.map(\.windowID)
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
            view.thumbnail = thumbnailProvider(item.windowID)
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
    /// La celda envuelve la Thumbnail con su margen y deja lugar al título debajo.
    static func cellSize(for thumbnail: ThumbnailSize) -> NSSize {
        NSSize(
            width: CGFloat(thumbnail.width) + 2 * cellInset,
            height: CGFloat(thumbnail.height) + 2 * cellInset + titleHeight + titleBottomOffset
        )
    }
    /// Ícono grande: lo único que hay en la celda mientras no llega la Thumbnail.
    static let iconSize: CGFloat = 72
    /// Ícono chico: encima de la Thumbnail, en su esquina inferior izquierda.
    static let badgeIconSize: CGFloat = 32
    /// Separación del ícono chico respecto de la esquina de la Thumbnail.
    static let badgeIconMargin: CGFloat = 4
    static let thumbnailCornerRadius: CGFloat = 6
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

/// Una celda de la grilla: la Thumbnail de la Window con el ícono de la App encima y, debajo,
/// el título. Mientras no hay Thumbnail muestra solo el ícono grande y el título.
private final class SwitcherCell: NSView {
    private let thumbnailView = NSImageView()
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var thumbnailArea = NSRect.zero

    var isSelected = false {
        didSet { needsDisplay = true }
    }

    /// Reemplaza la imagen sin pasar por vacío: una Thumbnail refrescada no parpadea.
    var thumbnail: CGImage? {
        didSet {
            guard thumbnail !== oldValue else { return }
            thumbnailView.image = thumbnail.map { NSImage(cgImage: $0, size: .zero) }
            thumbnailView.isHidden = thumbnail == nil
            layoutIcon()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Metrics.cellCornerRadius
        layer?.borderWidth = Metrics.selectionBorderWidth

        let inset = Metrics.cellInset
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

        let titleTop = label.frame.maxY
        thumbnailArea = NSRect(x: inset, y: titleTop, width: frame.width - 2 * inset, height: frame.height - inset - titleTop)
        thumbnailView.frame = thumbnailArea
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = Metrics.thumbnailCornerRadius
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.isHidden = true

        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(thumbnailView)
        addSubview(iconView)
        addSubview(label)
        layoutIcon()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    func configure(title: String, icon: NSImage?) {
        label.stringValue = title
        label.toolTip = title
        iconView.image = icon
    }

    private func layoutIcon() {
        if thumbnail == nil {
            let size = Metrics.iconSize
            iconView.frame = NSRect(
                x: thumbnailArea.midX - size / 2, y: thumbnailArea.midY - size / 2, width: size, height: size
            )
        } else {
            let size = Metrics.badgeIconSize
            iconView.frame = NSRect(x: thumbnailArea.minX + Metrics.badgeIconMargin, y: thumbnailArea.minY + Metrics.badgeIconMargin, width: size, height: size)
        }
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
