import AppKit
import ApplicationServices
import SwitchaleCore

/// API privada y estable de ApplicationServices para obtener el CGWindowID de un AXUIElement.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Lee un atributo de AX como `CFTypeRef`.
func axAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func axWindowID(_ element: AXUIElement) -> CGWindowID? {
    var id: CGWindowID = 0
    guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
    return id
}

/// Window viva conocida en la última foto, para que el activador la encuentre.
struct LiveWindow {
    let element: AXUIElement
    let app: NSRunningApplication
}

/// Fuente de Windows básica: Windows reales del Space actual (según AX), con orden de apilamiento de CGWindowList.
@MainActor
final class WindowSource {
    private(set) var live: [WindowID: LiveWindow] = [:]

    func snapshot() -> Snapshot {
        var stackByID: [CGWindowID: Int] = [:]
        var layerByID: [CGWindowID: Int] = [:]
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for (index, entry) in list.enumerated() {
            guard let number = entry[kCGWindowNumber as String] as? CGWindowID else { continue }
            stackByID[number] = index
            layerByID[number] = entry[kCGWindowLayer as String] as? Int ?? 0
        }

        var windows: [WindowInfo] = []
        var liveWindows: [WindowID: LiveWindow] = [:]
        var fallbackStack = list.count

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isTerminated {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.25)
            guard let axWindows = axAttribute(appElement, kAXWindowsAttribute) as? [AXUIElement] else { continue }

            for element in axWindows {
                guard let wid = axWindowID(element) else { continue }
                // Solo la capa normal.
                if let layer = layerByID[wid], layer != 0 { continue }
                // Solo subrol estándar o diálogo.
                let subrole = axAttribute(element, kAXSubroleAttribute) as? String
                guard subrole == kAXStandardWindowSubrole as String || subrole == kAXDialogSubrole as String else { continue }
                // Al menos 100×100.
                var size = CGSize.zero
                if let value = axAttribute(element, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
                    AXValueGetValue(value as! AXValue, .cgSize, &size)
                }
                guard size.width >= 100, size.height >= 100 else { continue }

                let minimized = (axAttribute(element, kAXMinimizedAttribute) as? Bool) ?? false
                var title = (axAttribute(element, kAXTitleAttribute) as? String) ?? ""
                if title.isEmpty { title = app.localizedName ?? "" }

                let stack: Int
                if let known = stackByID[wid] {
                    stack = known
                } else {
                    stack = fallbackStack
                    fallbackStack += 1
                }
                windows.append(WindowInfo(
                    id: Int(wid),
                    appID: Int(app.processIdentifier),
                    title: title,
                    isMinimized: minimized,
                    isAppHidden: app.isHidden,
                    stackIndex: stack
                ))
                liveWindows[Int(wid)] = LiveWindow(element: element, app: app)
            }
        }
        live = liveWindows
        return Snapshot(windows: windows)
    }
}
