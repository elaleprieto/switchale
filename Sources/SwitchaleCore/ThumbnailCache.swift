// Cache de Thumbnails por Window. La imagen es opaca para el núcleo: la captura
// (ScreenCaptureKit) y el dibujo viven en los adaptadores.

/// Tamaño máximo de una Thumbnail, en puntos. Sale de la configuración.
public struct ThumbnailSize: Sendable, Equatable {
    public var width: Int
    public var height: Int

    public init(width: Int = 160, height: Int = 100) {
        self.width = width
        self.height = height
    }
}

public struct ThumbnailCache<Image: Sendable>: Sendable {
    private struct Entry: Sendable {
        var image: Image
        var size: ThumbnailSize
        var capturedAt: Double
    }

    /// Segundos después de los cuales una Thumbnail se vuelve a capturar.
    private let refreshInterval: Double
    private var entries: [WindowID: Entry] = [:]
    private var capturing: Set<WindowID> = []
    /// Cuándo falló por última vez la captura de cada Window: no se reintenta antes de `refreshInterval`.
    private var failedAt: [WindowID: Double] = [:]
    private var screenRecording = true

    public init(refreshInterval: Double = 2) {
        self.refreshInterval = refreshInterval
    }

    /// La última Thumbnail guardada, aunque esté vieja: se muestra hasta que llega la nueva.
    public func image(for window: WindowID) -> Image? {
        entries[window]?.image
    }

    /// Actualiza el permiso de Grabación de pantalla. Sin él se descartan las Thumbnails y las
    /// capturas en curso. Devuelve true si se descartó algo y la vista tiene que volver a ícono y título.
    @discardableResult
    public mutating func updatePermission(screenRecording granted: Bool) -> Bool {
        screenRecording = granted
        guard !granted else { return false }
        let hadImages = !entries.isEmpty
        removeAll()
        return hadImages
    }

    /// Qué Windows de `windows` hay que capturar ahora, en el mismo orden. Sin Grabación de
    /// pantalla no hay nada que capturar.
    public func windowsToCapture(among windows: [WindowID], size: ThumbnailSize, now: Double) -> [WindowID] {
        guard screenRecording else { return [] }
        return windows.filter { id in
            guard !capturing.contains(id) else { return false }
            if let failed = failedAt[id], now - failed < refreshInterval { return false }
            guard let entry = entries[id] else { return true }
            return entry.size != size || now - entry.capturedAt >= refreshInterval
        }
    }

    public mutating func markCapturing(_ window: WindowID) {
        capturing.insert(window)
    }

    /// La captura falló: la Window no se vuelve a pedir hasta que pase `refreshInterval`.
    public mutating func captureFailed(_ window: WindowID, at now: Double) {
        guard capturing.remove(window) != nil else { return }
        failedAt[window] = now
    }

    /// Guarda el resultado de una captura pedida. Si la Window ya no se esperaba (se cerró o se
    /// perdió el permiso) el resultado se descarta. Devuelve si se guardó.
    @discardableResult
    public mutating func store(_ image: Image, for window: WindowID, size: ThumbnailSize, at now: Double) -> Bool {
        guard capturing.remove(window) != nil else { return false }
        failedAt[window] = nil
        entries[window] = Entry(image: image, size: size, capturedAt: now)
        return true
    }

    /// Descarta lo de las Windows que ya no existen.
    public mutating func prune(keeping windows: Set<WindowID>) {
        entries = entries.filter { windows.contains($0.key) }
        capturing = capturing.intersection(windows)
        failedAt = failedAt.filter { windows.contains($0.key) }
    }

    public mutating func removeAll() {
        entries = [:]
        capturing = []
        failedAt = [:]
    }
}
