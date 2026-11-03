import AppKit
import SwitchaleCore

/// Recibe eventos de los adaptadores, los pasa al núcleo y despacha los efectos.
@MainActor
final class Orchestrator {
    /// Activation Delay por defecto (la configurabilidad llega en otro ticket).
    private static let activationDelay: TimeInterval = 0.080

    private var core = SwitcherCore()
    private let source = WindowSource()
    private let activator = WindowActivator()
    private var timer: Timer?
    private var tap: EventTap?
    private var focus: FocusTracker?

    func start() {
        _ = core.send(.snapshot(source.snapshot()))

        let focus = FocusTracker { [weak self] id in self?.windowFocused(id) }
        self.focus = focus
        focus.start()
        if let front = NSWorkspace.shared.frontmostApplication {
            focus.reportFocusedWindow(pid: front.processIdentifier)
        }

        let tap = EventTap(
            onHotkey: { [weak self] scope, isRepeat in
                self?.hotkeyPressed(scope, isRepeat: isRepeat) ?? HotkeyResult(consume: false, sessionStarted: false)
            },
            onModifierReleased: { [weak self] in self?.dispatch(.modifierReleased) }
        )
        self.tap = tap
        tap.start()
    }

    private func windowFocused(_ id: Int) {
        // Una Window nueva puede no estar aún en la foto.
        _ = core.send(.windowFocused(id))
    }

    private func hotkeyPressed(_ scope: Scope, isRepeat: Bool) -> HotkeyResult {
        if !isRepeat {
            // Foto fresca para que cerradas y nuevas se reflejen antes de decidir.
            _ = core.send(.snapshot(source.snapshot()))
        }
        let effects = dispatch(.hotkeyPressed(scope))
        return HotkeyResult(
            consume: !effects.contains(.passEventToSystem),
            sessionStarted: effects.contains(.startActivationTimer)
        )
    }

    @discardableResult
    private func dispatch(_ event: SwitcherEvent) -> [SwitcherEffect] {
        let effects = core.send(event)
        for effect in effects {
            switch effect {
            case .startActivationTimer:
                timer?.invalidate()
                timer = Timer.scheduledTimer(withTimeInterval: Self.activationDelay, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.dispatch(.activationDelayElapsed) }
                }
            case .cancelActivationTimer:
                timer?.invalidate()
                timer = nil
            case .activate(let id):
                if let window = source.live[id] {
                    activator.activate(window)
                    _ = core.send(.windowFocused(id))
                }
            case .passEventToSystem:
                break // Lo resuelve el event tap según el valor de retorno.
            }
        }
        return effects
    }
}
