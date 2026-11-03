import AppKit
import ApplicationServices

/// Ejecuta el efecto "activar Window": restaura, muestra la App, sube solo esa Window y le da foco.
@MainActor
struct WindowActivator {
    /// Devuelve false sin tocar nada si la Window o su App ya no existen.
    @discardableResult
    func activate(_ handle: WindowHandle) -> Bool {
        let element = handle.element
        let app = handle.app
        guard !app.isTerminated, axAttribute(element, kAXRoleAttribute) != nil else { return false }
        if axIsMinimized(element) {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        if app.isHidden { app.unhide() }

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
        return true
    }

    /// Activa una Windowless App como el clic en su ícono del Dock: `openApplication` sobre una App
    /// ya en ejecución dispara el reopen, que normalmente abre su ventana por defecto.
    /// Devuelve false si la App ya no existe.
    @discardableResult
    func activateApp(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              let url = app.bundleURL
        else { return false }
        if app.isHidden { app.unhide() }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        return true
    }
}
