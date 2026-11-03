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

/// Elemento AX de una App con timeout corto, para que una App colgada no bloquee al switcher.
func axApplicationElement(pid: pid_t) -> AXUIElement {
    let element = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(element, 0.25)
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
