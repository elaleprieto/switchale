import AppKit
import ApplicationServices
import SwitchaleCore

/// Lo necesario para activar una Window conocida en la última foto.
struct WindowHandle {
    let element: AXUIElement
    let app: NSRunningApplication
}

/// Fuente de Windows: informa los datos de cada Window (Space, pantalla, Minimized, App Hidden);
/// qué entra en cada Switch Session lo decide el núcleo.
@MainActor
final class WindowSource {
    private(set) var handles: [WindowID: WindowHandle] = [:]

    func snapshot() -> Snapshot {
        let (cgInfo, onScreenIDs) = Self.cgWindowInfo()
        let currentScreen = Self.currentScreen()

        var windows: [Window] = []
        var apps: [AppInfo] = []
        var newHandles: [WindowID: WindowHandle] = [:]

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isTerminated {
            let appID = AppID(Int(app.processIdentifier))
            apps.append(AppInfo(id: appID, name: app.localizedName ?? ""))
            let appElement = axApplicationElement(pid: app.processIdentifier)
            guard let axWindows = axAttribute(appElement, kAXWindowsAttribute) as? [AXUIElement] else { continue }

            for element in axWindows {
                // Si el id no está en CGWindowList (o no es de la capa normal), no es una Window.
                guard let id = axWindowID(element),
                      let entry = cgInfo[id],
                      entry.layer == 0,
                      Self.isStandardWindow(element)
                else { continue }

                let isMinimized = axIsMinimized(element)
                // AX solo lista las Windows del Space actual (y las Minimized); lo que no está en
                // pantalla ni minimizado ni de una App oculta no se puede ubicar en el Space actual.
                let isInCurrentSpace = onScreenIDs.contains(id) || isMinimized || app.isHidden
                windows.append(Window(
                    id: id,
                    appID: appID,
                    title: (axAttribute(element, kAXTitleAttribute) as? String) ?? "",
                    screen: Self.screen(containing: entry.bounds) ?? currentScreen,
                    isInCurrentSpace: isInCurrentSpace,
                    isMinimized: isMinimized,
                    isAppHidden: app.isHidden,
                    stackIndex: entry.stackIndex
                ))
                newHandles[id] = WindowHandle(element: element, app: app)
            }
        }
        handles = newHandles
        return Snapshot(windows: windows, apps: apps, currentScreen: currentScreen)
    }

    // MARK: - CGWindowList

    private struct CGEntry {
        let layer: Int
        let stackIndex: Int
        let bounds: CGRect
    }

    private static func cgWindowInfo() -> ([WindowID: CGEntry], Set<WindowID>) {
        let all = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var entries: [WindowID: CGEntry] = [:]
        for (index, info) in all.enumerated() {
            guard let number = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            var bounds = CGRect.zero
            if let dictionary = info[kCGWindowBounds as String] as? NSDictionary {
                CGRectMakeWithDictionaryRepresentation(dictionary, &bounds)
            }
            entries[WindowID(Int(number))] = CGEntry(
                layer: info[kCGWindowLayer as String] as? Int ?? 0, stackIndex: index, bounds: bounds
            )
        }
        let onScreenIDs = Set(onScreen.compactMap { ($0[kCGWindowNumber as String] as? CGWindowID).map { WindowID(Int($0)) } })
        return (entries, onScreenIDs)
    }

    /// Solo subrol estándar o diálogo, de al menos 100×100.
    private static func isStandardWindow(_ element: AXUIElement) -> Bool {
        let subrole = axAttribute(element, kAXSubroleAttribute) as? String
        guard subrole == kAXStandardWindowSubrole as String || subrole == kAXDialogSubrole as String else { return false }
        var size = CGSize.zero
        if let value = axAttribute(element, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
            AXValueGetValue(value as! AXValue, .cgSize, &size)
        }
        return size.width >= 100 && size.height >= 100
    }

    // MARK: - Pantallas

    private static func currentScreen() -> ScreenID {
        let display = NSScreen.main.flatMap(displayID(of:)) ?? CGMainDisplayID()
        return ScreenID(Int(display))
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Pantalla con mayor intersección con `bounds` (coordenadas globales de CoreGraphics).
    private static func screen(containing bounds: CGRect) -> ScreenID? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetDisplaysWithRect(bounds, 16, &displays, &count) == .success, count > 0 else { return nil }
        let best = displays.prefix(Int(count)).max { first, second in
            CGDisplayBounds(first).intersection(bounds).area < CGDisplayBounds(second).intersection(bounds).area
        }
        return best.map { ScreenID(Int($0)) }
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
