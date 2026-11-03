import AppKit
import SwitchaleCore

/// Recibe eventos de los adaptadores, los pasa al núcleo y despacha todos sus efectos.
@MainActor
final class Orchestrator {
    /// Cada cuánto se refresca la foto mientras el Window Switcher está visible.
    private static let switcherRefreshInterval: TimeInterval = 0.5

    private let config = SwitcherConfig()
    private lazy var core = SwitcherCore(config: config)
    /// Thumbnails por Window; el núcleo decide qué capturar y cuándo, ScreenCaptureKit captura.
    private var thumbnails = ThumbnailCache<ThumbnailImage>()
    /// Windows que muestra el Window Switcher ahora.
    private var visibleWindows: [WindowID] = []
    private lazy var source = WindowSource { [weak self] snapshot in self?.dispatch(.snapshot(snapshot)) }
    private let activator = WindowActivator()
    private let switcherView = WindowSwitcherView()
    private var activationTimer: Timer?
    /// Mientras el Window Switcher está visible se refresca la foto, para que las Windows que se
    /// cierran salgan de la grilla.
    private var switcherRefreshTimer: Timer?
    private var tap: EventTap?
    private var focus: FocusTracker?

    func start() {
        source.refresh()

        let focus = FocusTracker(
            onFocus: { [weak self] id in self?.dispatch(.windowFocused(id)) },
            onAppsChanged: { [weak self] in self?.source.refresh() }
        )
        self.focus = focus
        focus.start()
        if let front = NSWorkspace.shared.frontmostApplication {
            focus.reportFocusedWindow(pid: front.processIdentifier)
        }

        switcherView.thumbnailSize = config.thumbnailSize
        switcherView.thumbnailProvider = { [weak self] id in self?.thumbnails.image(for: id)?.cgImage }

        let tap = EventTap { [weak self] event in self?.dispatch(event) ?? false }
        self.tap = tap
        tap.start()
    }

    /// Envía el evento al núcleo y ejecuta todos sus efectos. Devuelve true si el evento de teclado
    /// que lo originó debe consumirse.
    @discardableResult
    private func dispatch(_ event: SwitcherEvent) -> Bool {
        var consume = false
        for effect in core.send(event) {
            switch effect {
            case .startActivationTimer(let milliseconds):
                activationTimer?.invalidate()
                activationTimer = Timer.scheduledTimer(withTimeInterval: Double(milliseconds) / 1000, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { _ = self?.dispatch(.activationDelayElapsed) }
                }
            case .cancelActivationTimer:
                activationTimer?.invalidate()
                activationTimer = nil
            case .activate(let id):
                if let handle = source.handles[id], activator.activate(handle) {
                    dispatch(.windowFocused(id))
                } else {
                    dispatch(.activationFailed(id))
                }
            case .refreshSnapshot:
                source.refresh()
            case .consumeEvent:
                consume = true
            case .showSwitcher(let content):
                switcherView.show(content)
                visibleWindows = content.items.map(\.windowID)
                requestThumbnails()
                startSwitcherRefresh()
            case .updateSwitcher(let content):
                switcherView.update(content)
                visibleWindows = content.items.map(\.windowID)
                requestThumbnails()
            case .selectItem(let index):
                switcherView.select(index)
            case .hideSwitcher:
                switcherView.hide()
                visibleWindows = []
                switcherRefreshTimer?.invalidate()
                switcherRefreshTimer = nil
            }
        }
        return consume
    }

    private func startSwitcherRefresh() {
        switcherRefreshTimer?.invalidate()
        switcherRefreshTimer = Timer.scheduledTimer(withTimeInterval: Self.switcherRefreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.source.refresh()
                self?.requestThumbnails()
            }
        }
    }

    /// Pide las capturas que el núcleo considera necesarias. El panel ya está en pantalla: cada
    /// Thumbnail se completa cuando llega, sin tocar el resto de la grilla.
    private func requestThumbnails() {
        thumbnails.prune(keeping: Set(source.handles.keys))
        let now = ProcessInfo.processInfo.systemUptime
        let screenRecording = SystemPermissions.current().screenRecording
        if !screenRecording { thumbnails.removeAll() }
        let size = config.thumbnailSize
        let toCapture = thumbnails.windowsToCapture(
            among: visibleWindows, size: size, now: now, screenRecording: screenRecording
        )
        toCapture.forEach { thumbnails.markCapturing($0) }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        ThumbnailSource.capture(toCapture, size: size, scale: scale) { [weak self] id, image in
            guard let self else { return }
            if let image {
                thumbnails.store(image, for: id, size: size, at: ProcessInfo.processInfo.systemUptime)
                switcherView.thumbnailChanged(for: id)
            } else {
                thumbnails.captureFailed(id)
            }
        }
    }
}
