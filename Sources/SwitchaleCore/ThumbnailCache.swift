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

    public init(refreshInterval: Double = 2) {
        self.refreshInterval = refreshInterval
    }

    /// La última Thumbnail guardada, aunque esté vieja: se muestra hasta que llega la nueva.
    public func image(for window: WindowID) -> Image? {
        entries[window]?.image
    }

    /// Qué Windows de `windows` hay que capturar ahora, en el mismo orden. Sin Grabación de
    /// pantalla no hay nada que capturar.
    public func windowsToCapture(
        among windows: [WindowID], size: ThumbnailSize, now: Double, screenRecording: Bool
    ) -> [WindowID] {
        guard screenRecording else { return [] }
        return windows.filter { id in
            guard !capturing.contains(id) else { return false }
            guard let entry = entries[id] else { return true }
            return entry.size != size || now - entry.capturedAt >= refreshInterval
        }
    }

    public mutating func markCapturing(_ window: WindowID) {
        capturing.insert(window)
    }

    public mutating func captureFailed(_ window: WindowID) {
        capturing.remove(window)
    }

    public mutating func store(_ image: Image, for window: WindowID, size: ThumbnailSize, at now: Double) {
        capturing.remove(window)
        entries[window] = Entry(image: image, size: size, capturedAt: now)
    }

    /// Descarta lo de las Windows que ya no existen.
    public mutating func prune(keeping windows: Set<WindowID>) {
        entries = entries.filter { windows.contains($0.key) }
    }

    public mutating func removeAll() {
        entries = [:]
    }
}
