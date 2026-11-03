import AppKit
import SwitchaleCore

/// El Window Switcher en pantalla: un `NSPanel` no activante con fondo translúcido y una grilla
/// centrada en la pantalla que pasa a la siguiente fila cuando no entra. Solo dibuja lo que pide
/// el núcleo; el teclado lo recibe el event tap, así que el `NSPanel` nunca toma foco. Le informa
/// al núcleo los clics en las celdas y cuántas columnas tiene la grilla.
@MainActor
final class WindowSwitcherView {
    private let panel: NSPanel
    private let background = NSVisualEffectView()
    private var cells: [SwitcherCell] = []
    /// Tamaño de las Thumbnails, de la configuración.
    var thumbnailSize = ThumbnailSize() {
        didSet { cellSize = Metrics.cellSize(for: thumbnailSize) }
    }
    private var cellSize = Metrics.cellSize(for: ThumbnailSize())
    /// La Thumbnail ya capturada de una Window, si hay. Se consulta al armar la grilla, así un
    /// cambio de contenido no deja las celdas sin imagen.
    var thumbnailProvider: (WindowID) -> CGImage? = { _ in nil }
    /// Lo que se está mostrando, con la selección al día: si cambian las pantallas la grilla se
    /// rehace acá mismo, sin un efecto del núcleo que traiga el contenido.
    private var content: SwitcherContent?
    /// Columnas ya informadas al núcleo en esta Switch Session. Se olvidan en cada `show`, porque
    /// el núcleo arranca cada Switch Session sin columnas.
    private var reportedColumns: Int?
    private let onClick: (ItemID) -> Void
    private let onColumnsChanged: (Int) -> Void

    init(onClick: @escaping (ItemID) -> Void, onColumnsChanged: @escaping (Int) -> Void) {
        self.onClick = onClick
        self.onColumnsChanged = onColumnsChanged
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

        // Si cambia la resolución o la disposición de las pantallas con el Window Switcher abierto,
        // la grilla se rehace y puede cambiar de columnas.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible, let content = self.content else { return }
                self.layout(content)
            }
        }
    }

    func show(_ content: SwitcherContent) {
        reportedColumns = nil
        layout(content)
        panel.orderFrontRegardless()
    }

    func update(_ content: SwitcherContent) {
        layout(content)
    }

    /// Una Thumbnail nueva o refrescada: se cambia solo la imagen de esa celda.
    func thumbnailChanged(for window: WindowID) {
        guard let index = content?.items.firstIndex(where: { $0.id == .window(window) }),
              cells.indices.contains(index)
        else { return }
        cells[index].thumbnail = thumbnailProvider(window)
    }

    /// Se descartaron las Thumbnails (p. ej. se perdió el permiso): las celdas vuelven a ícono y título.
    func thumbnailsDiscarded() {
        for cell in cells { cell.thumbnail = nil }
    }

    func select(_ index: Int) {
        content?.selected = index
        for (offset, cell) in cells.enumerated() { cell.isSelected = offset == index }
    }

    func hide() {
        content = nil
        panel.orderOut(nil)
    }

    // MARK: - Grilla

    /// Arma la grilla y le informa al núcleo las columnas que quedaron, si cambiaron.
    private func layout(_ content: SwitcherContent) {
        self.content = content
        let items = content.items
        let screen = NSScreen.screens.first { $0.screenID == content.screen } ?? NSScreen.screens.first
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
        cells = items.enumerated().map { index, item in
            let row = index / columns
            let column = index % columns
            // Todas las filas arrancan a la izquierda del bloque, también la última si está
            // incompleta: así la columna i queda en la misma X en cada fila y ↑/↓ del núcleo, que
            // navegan por índice (± columnas), coinciden con lo que se ve.
            let x = Metrics.padding + CGFloat(column) * (cell.width + Metrics.spacing)
            let y = size.height - Metrics.padding - CGFloat(row + 1) * cell.height - CGFloat(row) * Metrics.spacing

            let view = SwitcherCell(frame: NSRect(origin: NSPoint(x: x, y: y), size: cell))
            view.configure(title: item.title, icon: Self.icon(for: item.appID), mark: item.mark)
            // Solo las Windows tienen Thumbnail: una Windowless App queda con ícono y título.
            if case .window(let window) = item.id { view.thumbnail = thumbnailProvider(window) }
            view.isSelected = index == content.selected
            view.onClick = { [weak self] in self?.onClick(item.id) }
            background.addSubview(view)
            return view
        }

        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        reportColumnsIfChanged(columns)
    }

    private func reportColumnsIfChanged(_ columns: Int) {
        guard columns != reportedColumns else { return }
        reportedColumns = columns
        onColumnsChanged(columns)
    }

    private static func icon(for app: AppID) -> NSImage? {
        NSRunningApplication(processIdentifier: app.pid)?.icon
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
    static let markerSize: CGFloat = 24
    static let markedIconAlpha: CGFloat = 0.5
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
    private let markerView = NSImageView()
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

    var onClick: (() -> Void)?

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
        markerView.contentTintColor = .secondaryLabelColor
        markerView.isHidden = true
        addSubview(thumbnailView)
        addSubview(iconView)
        addSubview(markerView)
        addSubview(label)
        layoutIcon()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    func configure(title: String, icon: NSImage?, mark: WindowMark) {
        // Marca visual: ícono atenuado y un símbolo en la esquina (minimizada u oculta).
        let look = Self.look(of: mark)
        label.stringValue = title
        label.toolTip = look.note.map { "\(title) (\($0))" } ?? title
        iconView.image = icon
        iconView.alphaValue = look.alpha
        thumbnailView.alphaValue = look.alpha
        markerView.image = look.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: look.note) }
        markerView.isHidden = look.symbol == nil
    }

    /// Cómo se ve cada marca: símbolo, nota (tooltip y accesibilidad) y alpha del ícono.
    private static func look(of mark: WindowMark) -> (symbol: String?, note: String?, alpha: CGFloat) {
        switch mark {
        case .none: (nil, nil, 1)
        case .minimized: ("minus.circle.fill", "minimizada", Metrics.markedIconAlpha)
        case .appHidden: ("eye.slash.fill", "App oculta", Metrics.markedIconAlpha)
        }
    }

    // El `NSPanel` nunca es key: sin esto el primer clic solo "activaría" la ventana.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Los clics sobre el ícono o el título los recibe la celda.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    // Vacío a propósito: la celda se queda con el mouseDown (por defecto `NSView` lo pasa al
    // responder siguiente) y el clic se resuelve en `mouseUp`.
    override func mouseDown(with event: NSEvent) {}

    /// El clic cuenta al soltar el botón dentro de la celda, como un botón.
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
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
        // La marca (minimizada u oculta) va en la esquina inferior derecha del ícono, esté grande o chico.
        markerView.frame = NSRect(
            x: iconView.frame.maxX - Metrics.markerSize / 2,
            y: iconView.frame.minY - Metrics.markerSize / 4,
            width: Metrics.markerSize, height: Metrics.markerSize
        )
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
