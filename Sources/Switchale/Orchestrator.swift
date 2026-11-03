import AppKit
import SwitchaleCore

/// Recibe eventos de los adaptadores, los pasa al núcleo y despacha todos sus efectos.
@MainActor
final class Orchestrator {
    /// Cada cuánto se refresca la foto mientras el Window Switcher está visible.
    private static let switcherRefreshInterval: TimeInterval = 0.5

    private var core = SwitcherCore()
    private lazy var source = WindowSource { [weak self] snapshot in self?.dispatch(.snapshot(snapshot)) }
    private let activator = WindowActivator()
    private lazy var switcherView = WindowSwitcherView(
        onClick: { [weak self] id in self?.dispatch(.windowClicked(id)) },
        onColumnsChanged: { [weak self] columns in self?.dispatch(.switcherColumnsChanged(columns)) }
    )
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
            onAppActivated: { [weak self] app in self?.dispatch(.appActivated(app)) },
            onAppsChanged: { [weak self] in self?.source.refresh() }
        )
        self.focus = focus
        focus.start()
        if let front = NSWorkspace.shared.frontmostApplication {
            focus.reportActivation(of: front)
        }

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
                startSwitcherRefresh()
            case .updateSwitcher(let content):
                switcherView.update(content)
            case .selectItem(let index):
                switcherView.select(index)
            case .hideSwitcher:
                switcherView.hide()
                switcherRefreshTimer?.invalidate()
                switcherRefreshTimer = nil
            }
        }
        return consume
    }

    private func startSwitcherRefresh() {
        switcherRefreshTimer?.invalidate()
        switcherRefreshTimer = Timer.scheduledTimer(withTimeInterval: Self.switcherRefreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.source.refresh() }
        }
    }
}
