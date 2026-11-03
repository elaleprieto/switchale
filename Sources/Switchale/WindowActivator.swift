import AppKit
import ApplicationServices

/// Ejecuta el efecto "activar Window": muestra la App, restaura la Window, sube solo esa Window y le da foco.
///
/// `unhide()` y desminimizar son asíncronos: el Raise/Focused solo corre cuando la App ya no está
/// Hidden y la Window ya no está Minimized (con un timeout corto, tras el cual se intenta igual).
/// Con APIs públicas no se pueden ocultar las otras Windows de la App: quedan visibles detrás de
/// la activada (ADR-0002/0003).
@MainActor
struct WindowActivator {
    private static let pollInterval: Duration = .milliseconds(20)
    private static let timeout: Duration = .milliseconds(500)

    /// Devuelve false sin tocar nada si la Window o su App ya no existen.
    @discardableResult
    func activate(_ handle: WindowHandle) -> Bool {
        let element = handle.element
        let app = handle.app
        guard !app.isTerminated, axAttribute(element, kAXRoleAttribute) != nil else { return false }
        let wasHidden = app.isHidden
        let wasMinimized = axIsMinimized(element)
        if !wasHidden && !wasMinimized {
            focus(element, of: app)
            return true
        }
        Task { @MainActor in
            // Primero la App y después la Window: una Window minimizada de una App oculta necesita las dos.
            if wasHidden {
                app.unhide()
                await Self.wait { !app.isHidden }
            }
            if wasMinimized {
                AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                await Self.wait { !axIsMinimized(element) }
            }
            guard !app.isTerminated else { return }
            focus(element, of: app)
        }
        return true
    }

    /// Reintenta cada `pollInterval` hasta que se cumpla la condición o venza el timeout.
    private static func wait(until condition: @MainActor () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: pollInterval)
        }
    }

    private func focus(_ element: AXUIElement, of app: NSRunningApplication) {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)

        // Desde macOS 14 la activación es cooperativa: una app LSUIElement en segundo plano no puede
        // forzar a otra al frente con `activate()`. Se la pone al frente por AX (no depende de que
        // switchale esté activa) y además se pide la activación cooperativa.
        let appElement = axApplicationElement(pid: app.processIdentifier)
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        NSApplication.shared.yieldActivation(to: app)
        app.activate(from: NSRunningApplication.current, options: [])
    }
}
