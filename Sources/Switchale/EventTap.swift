import AppKit
import ApplicationServices
import SwitchaleCore

/// Resultado de entregar un Hotkey al orquestador.
struct HotkeyResult {
    /// Consumir el evento original (false = dejarlo pasar al sistema).
    var consume: Bool
    /// Se abrió una Switch Session (hay que seguir el modificador).
    var sessionStarted: Bool
}

/// `CGEventTap` que reconoce los Hotkeys y el soltado del modificador.
/// Necesita Accesibilidad: sin ella no se instala y ⌘⇥ sigue siendo el nativo.
@MainActor
final class EventTap {
    private static let relevantFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
    // Hotkeys por defecto (la configurabilidad llega en otro ticket).
    private static let tabKey: Int64 = 48
    private static let backtickKey: Int64 = 50

    private let onHotkey: (Scope, Bool) -> HotkeyResult
    private let onModifierReleased: () -> Void
    private var port: CFMachPort?
    private var retryTimer: Timer?
    private var heldModifier: CGEventFlags?
    private var heldKey: Int64?

    init(onHotkey: @escaping (Scope, Bool) -> HotkeyResult, onModifierReleased: @escaping () -> Void) {
        self.onHotkey = onHotkey
        self.onModifierReleased = onModifierReleased
    }

    /// Instala el tap; si falta Accesibilidad, reintenta cada 2 s hasta que se otorgue.
    func start() {
        if install() { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.install() { self.retryTimer?.invalidate(); self.retryTimer = nil }
            }
        }
    }

    private func install() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.port = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    /// Devuelve true si hay que consumir el evento.
    fileprivate func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags, isRepeat: Bool) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false

        case .keyDown:
            let mods = flags.intersection(Self.relevantFlags)
            let scope: Scope
            let modifier: CGEventFlags
            if keyCode == Self.tabKey && mods == .maskCommand {
                scope = .allWindows; modifier = .maskCommand
            } else if keyCode == Self.backtickKey && mods == .maskAlternate {
                scope = .currentApp; modifier = .maskAlternate
            } else {
                return false
            }
            let result = onHotkey(scope, isRepeat)
            if result.sessionStarted {
                heldModifier = modifier
                heldKey = keyCode
            }
            return result.consume

        case .keyUp:
            return heldKey == keyCode

        case .flagsChanged:
            if let held = heldModifier, !flags.contains(held) {
                heldModifier = nil
                heldKey = nil
                onModifierReleased()
            }
            return false

        default:
            return false
        }
    }
}

private func eventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    let consume = MainActor.assumeIsolated {
        tap.handle(type: type, keyCode: keyCode, flags: flags, isRepeat: isRepeat)
    }
    return consume ? nil : Unmanaged.passUnretained(event)
}
