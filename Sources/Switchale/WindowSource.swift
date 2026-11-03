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
///
/// La foto se toma fuera del main thread: ahí corre el event tap, y una foto completa (AX contra
/// cada App) es lenta y le metería latencia a ⇥/Esc/soltar ⌘, o haría que macOS lo deshabilite por
/// timeout. Se toma una sola foto a la vez, en orden, y se entrega en el main thread; los pedidos
/// que llegan mientras tanto se juntan en una foto siguiente, así ninguna foto vieja pisa a una
/// más nueva.
@MainActor
final class WindowSource {
    private(set) var handles: [WindowID: WindowHandle] = [:]
    private let onSnapshot: (Snapshot) -> Void
    private let queue = DispatchQueue(label: "com.aleprieto.switchale.window-source", qos: .userInteractive)
    private var isCapturing = false
    private var needsAnotherCapture = false

    init(onSnapshot: @escaping (Snapshot) -> Void) {
        self.onSnapshot = onSnapshot
    }

    /// Pide una foto fresca; llega por `onSnapshot`.
    func refresh() {
        guard !isCapturing else {
            needsAnotherCapture = true
            return
        }
        isCapturing = true
        // Lo de AppKit (pantalla actual, Apps en ejecución) se lee acá, en el main thread.
        let input = CaptureInput(
            apps: NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated },
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            screens: Screens(mouse: Self.mouseScreen(), primary: ScreenID(display: CGMainDisplayID()))
        )
        queue.async { [weak self] in
            let capture = Self.capture(input)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.deliver(capture) }
            }
        }
    }

    private func deliver(_ capture: Capture) {
        isCapturing = false
        handles = capture.handles
        onSnapshot(capture.snapshot)
        if needsAnotherCapture {
            needsAnotherCapture = false
            refresh()
        }
    }

    // MARK: - Foto (fuera del main thread)

    /// `NSRunningApplication` y `AXUIElement` no están marcados `Sendable`, pero AX y las
    /// propiedades de `NSRunningApplication` se pueden leer desde cualquier hilo.
    private struct CaptureInput: @unchecked Sendable {
        let apps: [NSRunningApplication]
        let frontmostPID: pid_t?
        let screens: Screens
    }

    private struct Capture: @unchecked Sendable {
        let snapshot: Snapshot
        let handles: [WindowID: WindowHandle]
    }

    private nonisolated static func capture(_ input: CaptureInput) -> Capture {
        let (cgInfo, onScreenIDs) = cgWindowInfo()
        // La Window con foco según AX, leída al tomar la foto (la pantalla actual sale de ella).
        let focusedWindow = input.frontmostPID.flatMap { axFocusedWindowID(pid: $0) }

        var windows: [Window] = []
        var apps: [AppInfo] = []
        var newHandles: [WindowID: WindowHandle] = [:]

        for app in input.apps {
            let appID = AppID(Int(app.processIdentifier))
            apps.append(AppInfo(id: appID, name: app.localizedName ?? ""))
            let appElement = axApplicationElement(pid: app.processIdentifier)
            guard let axWindows = axAttribute(appElement, kAXWindowsAttribute) as? [AXUIElement] else { continue }

            for element in axWindows {
                // Si el id no está en CGWindowList (o no es de la capa normal), no es una Window.
                guard let id = axWindowID(element),
                      let entry = cgInfo[id],
                      entry.layer == 0,
                      isStandardWindow(element)
                else { continue }

                let isMinimized = axIsMinimized(element)
                // AX solo lista las Windows del Space actual (y las Minimized); lo que no está en
                // pantalla ni minimizado ni de una App oculta no se puede ubicar en el Space actual.
                let isInCurrentSpace = onScreenIDs.contains(id) || isMinimized || app.isHidden
                windows.append(Window(
                    id: id,
                    appID: appID,
                    title: (axAttribute(element, kAXTitleAttribute) as? String) ?? "",
                    screen: screen(containing: entry.bounds) ?? input.screens.mouse,
                    isInCurrentSpace: isInCurrentSpace,
                    isMinimized: isMinimized,
                    isAppHidden: app.isHidden,
                    stackIndex: entry.stackIndex
                ))
                newHandles[id] = WindowHandle(element: element, app: app)
            }
        }
        return Capture(
            snapshot: Snapshot(windows: windows, apps: apps, focusedWindow: focusedWindow, screens: input.screens),
            handles: newHandles
        )
    }

    // MARK: - CGWindowList

    private struct CGEntry {
        let layer: Int
        let stackIndex: Int
        let bounds: CGRect
    }

    private nonisolated static func cgWindowInfo() -> ([WindowID: CGEntry], Set<WindowID>) {
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
    private nonisolated static func isStandardWindow(_ element: AXUIElement) -> Bool {
        let subrole = axAttribute(element, kAXSubroleAttribute) as? String
        guard subrole == kAXStandardWindowSubrole as String || subrole == kAXDialogSubrole as String else { return false }
        var size = CGSize.zero
        if let value = axAttribute(element, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
            AXValueGetValue(value as! AXValue, .cgSize, &size)
        }
        return size.width >= 100 && size.height >= 100
    }

    // MARK: - Pantallas

    /// La pantalla donde está el mouse; si no cae en ninguna, la principal.
    private static func mouseScreen() -> ScreenID {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }?.screenID
            ?? ScreenID(display: CGMainDisplayID())
    }

    /// Pantalla con mayor intersección con `bounds` (coordenadas globales de CoreGraphics).
    private nonisolated static func screen(containing bounds: CGRect) -> ScreenID? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetDisplaysWithRect(bounds, 16, &displays, &count) == .success, count > 0 else { return nil }
        let best = displays.prefix(Int(count)).max { first, second in
            CGDisplayBounds(first).intersection(bounds).area < CGDisplayBounds(second).intersection(bounds).area
        }
        return best.map(ScreenID.init(display:))
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
