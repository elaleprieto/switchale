import AppKit
import ApplicationServices
import SwitchaleCore

/// `CGEventTap` que traduce teclas y modificadores a eventos del núcleo.
/// Solo aplica la decisión de consumir que devuelve el núcleo; no tiene lógica de sesión.
/// Necesita Accesibilidad: sin ella no se instala y ⌘⇥ sigue siendo el nativo.
@MainActor
final class EventTap {
    /// Entrega un evento al núcleo y devuelve true si hay que consumir el evento de teclado.
    private let onEvent: (SwitcherEvent) -> Bool
    private var port: CFMachPort?
    private var retryTimer: Timer?

    init(onEvent: @escaping (SwitcherEvent) -> Bool) {
        self.onEvent = onEvent
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
        syncModifiers()
        return true
    }

    /// Relee los modificadores reales: si el tap estuvo caído y se perdió el soltado, el núcleo cierra la sesión.
    private func syncModifiers() {
        _ = onEvent(.modifiersChanged(modifiers(CGEventSource.flagsState(.combinedSessionState))))
    }

    /// Devuelve true si hay que consumir el evento. `translated` es nil para tipos que no interesan.
    fileprivate func handle(type: CGEventType, translated: SwitcherEvent?) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            syncModifiers()
            return false
        default:
            return translated.map(onEvent) ?? false
        }
    }
}

private func translate(_ type: CGEventType, _ event: CGEvent) -> SwitcherEvent? {
    func keyCode() -> KeyCode { KeyCode(Int(event.getIntegerValueField(.keyboardEventKeycode))) }
    switch type {
    case .keyDown:
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        return .keyDown(keyCode(), modifiers(event.flags), isRepeat: isRepeat)
    case .keyUp:
        return .keyUp(keyCode())
    case .flagsChanged:
        return .modifiersChanged(modifiers(event.flags))
    default:
        return nil
    }
}

private func modifiers(_ flags: CGEventFlags) -> Modifiers {
    var result: Modifiers = []
    if flags.contains(.maskCommand) { result.insert(.command) }
    if flags.contains(.maskShift) { result.insert(.shift) }
    if flags.contains(.maskAlternate) { result.insert(.option) }
    if flags.contains(.maskControl) { result.insert(.control) }
    return result
}

private func eventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ context: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let context else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(context).takeUnretainedValue()
    let translated = translate(type, event)
    let consume = MainActor.assumeIsolated { tap.handle(type: type, translated: translated) }
    return consume ? nil : Unmanaged.passUnretained(event)
}
