import AppKit
import ApplicationServices
import SwitchaleCore

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
        let app = handle.app
        if app.isSwitchale { return activateOwn(handle.id) }
        if handle.isInOtherSpace { return activateInOtherSpace(handle) }
        guard let element = handle.element, !app.isTerminated, axAttribute(element, kAXRoleAttribute) != nil
        else { return false }
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

    /// Una Window de otro Space: `Spaces` pone al frente su App con ella como key, y macOS cambia
    /// a su Space. Ya en ese Space, AX la lista y se le da foco como a cualquier otra (si AX la
    /// listaba de antes, con ese elemento). Devuelve false si la App terminó o `Spaces` falló.
    private func activateInOtherSpace(_ handle: WindowHandle) -> Bool {
        let app = handle.app
        guard !app.isTerminated else { return false }
        if app.isHidden { app.unhide() }
        guard Spaces.focus(handle.id, pid: app.processIdentifier) else { return false }
        Task { @MainActor in
            var element = handle.element
            await Self.wait {
                element = element ?? Self.axWindow(handle.id, pid: app.processIdentifier)
                return element != nil
            }
            guard let element, !app.isTerminated else { return }
            if axIsMinimized(element) {
                AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            focus(element, of: app)
        }
        return true
    }

    /// El elemento AX de la Window con este id, si AX la lista (ya en su Space).
    private static func axWindow(_ id: WindowID, pid: pid_t) -> AXUIElement? {
        let windows = axAttribute(axApplicationElement(pid: pid), kAXWindowsAttribute) as? [AXUIElement] ?? []
        return windows.first { axWindowID($0) == id }
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

    /// Una Window de switchale se activa con AppKit: AX contra el propio proceso desde el main
    /// thread bloquea hasta el timeout.
    private func activateOwn(_ id: WindowID) -> Bool {
        guard let window = NSApp.window(withWindowNumber: id.rawValue) else { return false }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.unhide(nil)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        return true
    }

    /// Activa una Windowless App como el clic en su ícono del Dock: `openApplication` sobre una App
    /// ya en ejecución dispara el reopen (que también la muestra si estaba Hidden), que normalmente
    /// abre su ventana por defecto. `completion` recibe false, en el main thread, si la App ya no
    /// existe o el sistema no pudo abrirla.
    func activateApp(pid: pid_t, completion: @escaping @MainActor (Bool) -> Void) {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              let url = app.bundleURL
        else {
            completion(false)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(error == nil) }
            }
        }
    }
}
