import AppKit
import ApplicationServices

/// Ejecuta el efecto "activar Window": restaura, muestra la App, sube la Window y le da foco.
@MainActor
struct WindowActivator {
    func activate(_ window: LiveWindow) {
        let element = window.element
        if (axAttribute(element, kAXMinimizedAttribute) as? Bool) == true {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        if window.app.isHidden {
            window.app.unhide()
        }
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        window.app.activate(options: [.activateAllWindows])
        // Vuelve a subir la Window elegida por encima del resto de la App.
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }
}
