import CoreGraphics
import ScreenCaptureKit
import SwitchaleCore

/// La imagen de una Thumbnail. `CGImage` es inmutable, así que se puede pasar entre hilos.
struct ThumbnailImage: @unchecked Sendable {
    let cgImage: CGImage
}

/// Captura de Thumbnails con ScreenCaptureKit, siempre asíncrona: nunca bloquea el main thread
/// ni el event tap. Qué capturar y cuándo lo decide el núcleo (`ThumbnailCache`).
enum ThumbnailSource {
    /// `SCWindow` es inmutable pero no está marcado `Sendable`.
    fileprivate struct Target: @unchecked Sendable {
        let window: SCWindow?
    }

    /// Cuánto se reutiliza el `SCShareableContent` entre lotes, en segundos.
    private static let contentTTL: TimeInterval = 1
    /// Capturas simultáneas como máximo.
    private static let maxConcurrentCaptures = 4

    private struct CachedContent: @unchecked Sendable {
        let windows: [WindowID: Target]
        let fetchedAt: Date
    }

    private actor ContentCache {
        private var cached: CachedContent?

        func windows() async -> [WindowID: Target] {
            if let cached, Date().timeIntervalSince(cached.fetchedAt) < ThumbnailSource.contentTTL {
                return cached.windows
            }
            let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let windows = Dictionary(
                (content?.windows ?? []).map { (WindowID(Int($0.windowID)), Target(window: $0)) },
                uniquingKeysWith: { first, _ in first }
            )
            cached = CachedContent(windows: windows, fetchedAt: Date())
            return windows
        }
    }

    private static let contentCache = ContentCache()

    /// Captura las Thumbnails de `windows`, con a lo sumo `maxConcurrentCaptures` a la vez, y llama
    /// a `deliver` por cada una (en el main actor) con la imagen o nil si la Window no se pudo
    /// capturar (cerrada, en otro Space, Minimized o sin permiso).
    static func capture(
        _ windows: [WindowID],
        size: ThumbnailSize,
        scale: CGFloat,
        deliver: @escaping @MainActor (WindowID, ThumbnailImage?) -> Void
    ) {
        guard !windows.isEmpty else { return }
        Task.detached(priority: .userInitiated) {
            let byID = await contentCache.windows()
            await withTaskGroup(of: (WindowID, ThumbnailImage?).self) { group in
                var pending = windows.makeIterator()
                func addNext(to group: inout TaskGroup<(WindowID, ThumbnailImage?)>) {
                    guard let id = pending.next() else { return }
                    let target = byID[id] ?? Target(window: nil)
                    group.addTask { (id, await image(of: target.window, size: size, scale: scale)) }
                }
                for _ in 0..<maxConcurrentCaptures { addNext(to: &group) }
                for await (id, image) in group {
                    await deliver(id, image)
                    addNext(to: &group)
                }
            }
        }
    }

    private static func image(of window: SCWindow?, size: ThumbnailSize, scale: CGFloat) async -> ThumbnailImage? {
        guard let window, window.frame.width > 0, window.frame.height > 0 else { return nil }
        let configuration = SCStreamConfiguration()
        // Cabe en el tamaño pedido conservando la proporción.
        let fit = min(CGFloat(size.width) / window.frame.width, CGFloat(size.height) / window.frame.height, 1)
        configuration.width = max(1, Int(window.frame.width * fit * scale))
        configuration.height = max(1, Int(window.frame.height * fit * scale))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let filter = SCContentFilter(desktopIndependentWindow: window)
        guard let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        else { return nil }
        return ThumbnailImage(cgImage: cgImage)
    }
}
