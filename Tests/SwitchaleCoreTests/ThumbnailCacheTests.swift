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
        #expect(cache.windowsToCapture(among: [a, b], size: size, now: 0) == [a, b])
        cache.markCapturing(a)
        cache.store("A", for: a, size: size, at: 0)
        #expect(cache.windowsToCapture(among: [a, b], size: size, now: 1) == [b])
        #expect(cache.image(for: a) == "A")
    }

    @Test("Sin permiso de Grabación de pantalla no se captura nada")
    func noScreenRecording() {
        var cache = cache()
        cache.updatePermission(screenRecording: false)
        #expect(cache.windowsToCapture(among: [a, b], size: size, now: 0).isEmpty)
    }

    @Test("Una Thumbnail vieja se vuelve a capturar pero se sigue mostrando hasta que llega la nueva")
    func staleIsRefreshedWithoutFlicker() {
        var cache = cache(refreshInterval: 5)
        cache.markCapturing(a)
        cache.store("A1", for: a, size: size, at: 0)
        #expect(cache.windowsToCapture(among: [a], size: size, now: 5) == [a])
        #expect(cache.image(for: a) == "A1")
        cache.markCapturing(a)
        cache.store("A2", for: a, size: size, at: 5)
        #expect(cache.image(for: a) == "A2")
        #expect(cache.windowsToCapture(among: [a], size: size, now: 6).isEmpty)
    }

    @Test("Una captura en curso no se pide de nuevo; si falla se puede reintentar")
    func inFlight() {
        var cache = cache()
        cache.markCapturing(a)
        #expect(cache.windowsToCapture(among: [a], size: size, now: 0).isEmpty)
        cache.captureFailed(a, at: 0)
        #expect(cache.windowsToCapture(among: [a], size: size, now: 5) == [a])
    }

    @Test("Si cambia el tamaño de configuración se recaptura, mostrando la anterior mientras tanto")
    func sizeChange() {
        var cache = cache()
        cache.markCapturing(a)
        cache.store("A", for: a, size: size, at: 0)
        let bigger = ThumbnailSize(width: 400, height: 240)
        #expect(cache.windowsToCapture(among: [a], size: bigger, now: 1) == [a])
        #expect(cache.image(for: a) == "A")
    }

    @Test("Las Windows que ya no existen salen del cache")
    func prune() {
        var cache = cache()
        cache.markCapturing(a)
        cache.store("A", for: a, size: size, at: 0)
        cache.markCapturing(b)
        cache.store("B", for: b, size: size, at: 0)
        cache.prune(keeping: [b])
        #expect(cache.image(for: a) == nil)
        #expect(cache.image(for: b) == "B")
    }

    @Test("Al perder el permiso se descartan las Thumbnails guardadas")
    func clear() {
        var cache = cache()
        cache.markCapturing(a)
        cache.store("A", for: a, size: size, at: 0)
        cache.removeAll()
        #expect(cache.image(for: a) == nil)
    }

    @Test("Prune y removeAll también olvidan las capturas en curso, y su resultado tardío se descarta")
    func lateResultIsDiscarded() {
        var cache = cache()
        cache.markCapturing(a)
        cache.markCapturing(b)
        cache.prune(keeping: [b])
        let storedA = cache.store("A", for: a, size: size, at: 1)
        #expect(!storedA)
        #expect(cache.image(for: a) == nil)
        cache.removeAll()
        let storedB = cache.store("B", for: b, size: size, at: 1)
        #expect(!storedB)
        #expect(cache.image(for: b) == nil)
        #expect(cache.windowsToCapture(among: [a, b], size: size, now: 1) == [a, b])
    }

    @Test("Una captura fallida no se reintenta hasta que pasa el intervalo")
    func failureBackoff() {
        var cache = cache(refreshInterval: 5)
        cache.markCapturing(a)
        cache.captureFailed(a, at: 10)
        #expect(cache.windowsToCapture(among: [a, b], size: size, now: 12).contains(a) == false)
        #expect(cache.windowsToCapture(among: [a], size: size, now: 15) == [a])
    }

    @Test("Perder el permiso descarta las Thumbnails, avisa, e ignora las capturas en curso")
    func permissionLoss() {
        var cache = cache()
        cache.markCapturing(a)
        cache.store("A", for: a, size: size, at: 0)
        cache.markCapturing(b)
        let discarded = cache.updatePermission(screenRecording: false)
        #expect(discarded)
        #expect(cache.image(for: a) == nil)
        let storedB = cache.store("B", for: b, size: size, at: 1)
        #expect(!storedB)
        let discardedAgain = cache.updatePermission(screenRecording: false)
        #expect(!discardedAgain)
        cache.updatePermission(screenRecording: true)
        #expect(cache.windowsToCapture(among: [a], size: size, now: 1) == [a])
    }
}
