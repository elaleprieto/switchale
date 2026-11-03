import Testing
import SwitchaleCore

@Suite("Thumbnails")
struct ThumbnailCacheTests {
    let size = ThumbnailSize(width: 200, height: 120)
    let a = WindowID(1)
    let b = WindowID(2)

    func cache(refreshInterval: Double = 5) -> ThumbnailCache<String> {
        ThumbnailCache(refreshInterval: refreshInterval)
    }

    @Test("Sin Thumbnail guardada hay que capturarla; con una fresca, no")
    func capturesOnlyMissing() {
        var cache = cache()
        #expect(cache.windowsToCapture(among: [a, b], size: size, now: 0, screenRecording: true) == [a, b])
        cache.store("A", for: a, size: size, at: 0)
        #expect(cache.windowsToCapture(among: [a, b], size: size, now: 1, screenRecording: true) == [b])
        #expect(cache.image(for: a) == "A")
    }

    @Test("Sin permiso de Grabación de pantalla no se captura nada")
    func noScreenRecording() {
        let cache = cache()
        #expect(cache.windowsToCapture(among: [a, b], size: size, now: 0, screenRecording: false).isEmpty)
    }

    @Test("Una Thumbnail vieja se vuelve a capturar pero se sigue mostrando hasta que llega la nueva")
    func staleIsRefreshedWithoutFlicker() {
        var cache = cache(refreshInterval: 5)
        cache.store("A1", for: a, size: size, at: 0)
        #expect(cache.windowsToCapture(among: [a], size: size, now: 5, screenRecording: true) == [a])
        #expect(cache.image(for: a) == "A1")
        cache.store("A2", for: a, size: size, at: 5)
        #expect(cache.image(for: a) == "A2")
        #expect(cache.windowsToCapture(among: [a], size: size, now: 6, screenRecording: true).isEmpty)
    }

    @Test("Una captura en curso no se pide de nuevo; si falla se puede reintentar")
    func inFlight() {
        var cache = cache()
        cache.markCapturing(a)
        #expect(cache.windowsToCapture(among: [a], size: size, now: 0, screenRecording: true).isEmpty)
        cache.captureFailed(a)
        #expect(cache.windowsToCapture(among: [a], size: size, now: 0, screenRecording: true) == [a])
    }

    @Test("Si cambia el tamaño de configuración se recaptura, mostrando la anterior mientras tanto")
    func sizeChange() {
        var cache = cache()
        cache.store("A", for: a, size: size, at: 0)
        let bigger = ThumbnailSize(width: 400, height: 240)
        #expect(cache.windowsToCapture(among: [a], size: bigger, now: 1, screenRecording: true) == [a])
        #expect(cache.image(for: a) == "A")
    }

    @Test("Las Windows que ya no existen salen del cache")
    func prune() {
        var cache = cache()
        cache.store("A", for: a, size: size, at: 0)
        cache.store("B", for: b, size: size, at: 0)
        cache.prune(keeping: [b])
        #expect(cache.image(for: a) == nil)
        #expect(cache.image(for: b) == "B")
    }

    @Test("Al perder el permiso se descartan las Thumbnails guardadas")
    func clear() {
        var cache = cache()
        cache.store("A", for: a, size: size, at: 0)
        cache.removeAll()
        #expect(cache.image(for: a) == nil)
    }
}
