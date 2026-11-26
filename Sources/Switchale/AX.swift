import ApplicationServices
import SwitchaleCore

// Único archivo que toca la API privada `_AXUIElementGetWindow` (ADR-0003).
// Todo el resto de la app obtiene ids de Window y helpers de AX desde acá.

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Lee un atributo de AX como `CFTypeRef`.
func axAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

/// Id de Window (CGWindowID) de un elemento AX.
func axWindowID(_ element: AXUIElement) -> WindowID? {
    var id: CGWindowID = 0
    guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
    return WindowID(Int(id))
}

/// Timeout de cada consulta AX: una App colgada no puede bloquear al switcher.
private let axMessagingTimeout: Float = 0.25

/// Elemento AX de una App con timeout corto.
func axApplicationElement(pid: pid_t) -> AXUIElement {
    let element = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(element, axMessagingTimeout)
    return element
}

/// Las Windows que lista AX para esta App, cada una con timeout corto: el timeout del elemento de
/// la App no pasa a los elementos que devuelve, que usarían el del sistema (unos 6 s).
func axWindowElements(of app: AXUIElement) -> [AXUIElement]? {
    guard let windows = axAttribute(app, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
    for window in windows { AXUIElementSetMessagingTimeout(window, axMessagingTimeout) }
    return windows
}

/// El mismo elemento con el timeout del sistema, para actuar sobre él: activar o cerrar una
/// Window de una App que tarda no tiene que fallar por el timeout corto de la foto.
func axWithDefaultTimeout(_ element: AXUIElement) -> AXUIElement {
    AXUIElementSetMessagingTimeout(element, 0)
    return element
}

func axIsMinimized(_ element: AXUIElement) -> Bool {
    (axAttribute(element, kAXMinimizedAttribute) as? Bool) ?? false
}

/// Id de la Window enfocada de una App, si la hay.
func axFocusedWindowID(pid: pid_t) -> WindowID? {
    guard let value = axAttribute(axApplicationElement(pid: pid), kAXFocusedWindowAttribute),
          CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    return axWindowID(value as! AXUIElement)
}
