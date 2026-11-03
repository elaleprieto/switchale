import AppKit
import SwitchaleCore

/// Recibe eventos de los adaptadores, los pasa al núcleo y despacha todos sus efectos.
@MainActor
final class Orchestrator {
    private var core = SwitcherCore()
    private let source = WindowSource()
    private let activator = WindowActivator()
    private var activationTimer: Timer?
    private var tap: EventTap?
    private var focus: FocusTracker?

    func start() {
        refreshSnapshot()

        let focus = FocusTracker(
            onFocus: { [weak self] id in self?.dispatch(.windowFocused(id)) },
            onAppsChanged: { [weak self] in self?.refreshSnapshot() }
        )
        self.focus = focus
        focus.start()
        if let front = NSWorkspace.shared.frontmostApplication {
            focus.reportFocusedWindow(pid: front.processIdentifier)
        }

        let tap = EventTap { [weak self] event in self?.dispatch(event) ?? false }
        self.tap = tap
        tap.start()
    }

    private func refreshSnapshot() {
        dispatch(.snapshot(source.snapshot()))
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
                    MainActor.assumeIsolated { self?.dispatch(.activationDelayElapsed) }
                }
            case .cancelActivationTimer:
                activationTimer?.invalidate()
                activationTimer = nil
            case .activate(let id):
                if let handle = source.handles[id] {
                    activator.activate(handle)
                    dispatch(.windowFocused(id))
                }
            case .refreshSnapshot:
                // Fuera del callback del tap: la foto completa es lenta y el tap tiene timeout.
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated { self?.refreshSnapshot() }
                }
            case .consumeEvent:
                consume = true
            }
        }
        return consume
    }
}
