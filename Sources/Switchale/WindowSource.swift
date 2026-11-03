import AppKit
import ApplicationServices
import SwitchaleCore

/// Lo necesario para activar una Window conocida en la última foto.
struct WindowHandle {
    let id: WindowID
    /// Nil para las Windows de otros Spaces que AX no lista: se activan por `Spaces`.
    let element: AXUIElement?
    let app: NSRunningApplication
    /// Si es de otro Space y se encontró con la opción "Windows de otros Spaces" activada: activarla
    /// cambia de Space (con `Spaces`).
    let isInOtherSpace: Bool
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
    /// Incluir las Windows de otros Spaces en las próximas fotos. Solo con esto activado se usan
    /// las APIs privadas de `Spaces`, y solo si están disponibles.
    var includesOtherSpaces = false
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
            apps: NSWorkspace.shared.runningApplications.filter { $0.listsWindowsInSwitcher && !$0.isTerminated },
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            screens: Screens(mouse: Self.mouseScreen(), primary: ScreenID(display: CGMainDisplayID())),
            includesOtherSpaces: includesOtherSpaces
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
        let includesOtherSpaces: Bool
    }

    private struct Capture: @unchecked Sendable {
        let snapshot: Snapshot
        let handles: [WindowID: WindowHandle]
    }

    private nonisolated static func capture(_ input: CaptureInput) -> Capture {
        let cg = cgWindowInfo()
        // La Window con foco según AX, leída al tomar la foto (la pantalla actual sale de ella).
        let focusedWindow = input.frontmostPID.flatMap { axFocusedWindowID(pid: $0) }

        var windows: [Window] = []
        var windowlessApps: [AppID] = []
        var apps: [AppInfo] = []
        var newHandles: [WindowID: WindowHandle] = [:]
        /// Todas las ventanas que lista AX, sean Windows o no: las de otros Spaces son las que no.
        var axListed = Set<WindowID>()
        // Con la opción desactivada no se llama a `Spaces` (ni a ninguna API privada de SkyLight).
        let otherSpacesIDs = input.includesOtherSpaces ? Spaces.windowIDsInAllSpaces() : nil

        for app in input.apps {
            let appID = AppID(pid: app.processIdentifier)
            apps.append(AppInfo(id: appID, name: app.localizedName ?? ""))
            let appElement = axApplicationElement(pid: app.processIdentifier)
            let axWindows = axAttribute(appElement, kAXWindowsAttribute) as? [AXUIElement] ?? []
            var hasWindows = false

            for element in axWindows {
                let id = axWindowID(element)
                if let id { axListed.insert(id) }
                // Si el id no está en CGWindowList (o no es de la capa normal), no es una Window.
                guard let id,
                      let entry = cg.entries[id],
                      entry.layer == 0,
                      isStandardWindow(element)
                else { continue }

                let isMinimized = axIsMinimized(element)
                // AX solo lista las Windows del Space actual (y las Minimized); lo que no está en
                // pantalla ni minimizado ni de una App oculta no se puede ubicar en el Space actual.
                let isInCurrentSpace = cg.onScreenIDs.contains(id) || isMinimized || app.isHidden
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
                newHandles[id] = WindowHandle(
                    id: id, element: element, app: app,
                    isInOtherSpace: otherSpacesIDs != nil && !isInCurrentSpace
                )
                hasWindows = true
            }
            // Windowless: sin Windows nuestras y sin ventanas normales en CoreGraphics (que sí ve
            // las de otros Spaces, que AX no lista).
            if !hasWindows, !cg.pidsWithNormalWindows.contains(app.processIdentifier) {
                windowlessApps.append(appID)
            }
        }
        if let otherSpacesIDs {
            let appsByPID = Dictionary(input.apps.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
            // Las de otros Spaces que AX no lista: ventanas normales de CoreGraphics, de una App
            // del Window Switcher, que no están en pantalla.
            for id in otherSpacesIDs where !axListed.contains(id) && !cg.onScreenIDs.contains(id) {
                guard let entry = cg.entries[id], entry.isNormal, let app = appsByPID[entry.pid] else { continue }
                windows.append(Window(
                    id: id,
                    appID: AppID(pid: entry.pid),
                    // CoreGraphics da el título solo con Grabación de pantalla; si no, el núcleo
                    // muestra el nombre de la App.
                    title: entry.title,
                    screen: screen(containing: entry.bounds) ?? input.screens.mouse,
                    isInCurrentSpace: false,
                    isMinimized: false,
                    isAppHidden: app.isHidden,
                    stackIndex: entry.stackIndex
                ))
                newHandles[id] = WindowHandle(id: id, element: nil, app: app, isInOtherSpace: true)
            }
        }
        return Capture(
            snapshot: Snapshot(
                windows: windows, apps: apps, focusedWindow: focusedWindow, screens: input.screens,
                windowlessApps: windowlessApps
            ),
            handles: newHandles
        )
    }

    // MARK: - CGWindowList

    private struct CGEntry {
        let layer: Int
        let stackIndex: Int
        let bounds: CGRect
        let pid: pid_t
        let title: String
        /// Ventana normal según `isNormalCGWindow`.
        let isNormal: Bool
    }

    private struct CGInfo {
        let entries: [WindowID: CGEntry]
        let onScreenIDs: Set<WindowID>
        /// Dueños de al menos una ventana normal (ver `isNormalCGWindow`).
        let pidsWithNormalWindows: Set<pid_t>
    }

    /// Tamaño mínimo (ancho y alto) de una ventana para contar como Window.
    private nonisolated static let minimumWindowSize: CGFloat = 100

    /// Ventana normal en CoreGraphics: capa 0, de tamaño mínimo y visible (alpha > 0). `.optionAll`
    /// también lista ventanas que la App sacó de pantalla (orderOut) sin cerrarlas; ésas no cuentan,
    /// si no una App sin Windows reales (p. ej. Finder) nunca sería Windowless. Las ventanas de
    /// otros Spaces siguen contando: no están en pantalla pero son reales, y AX no las lista.
    private nonisolated static func isNormalCGWindow(layer: Int, bounds: CGRect, alpha: Double) -> Bool {
        layer == 0 && bounds.width >= minimumWindowSize && bounds.height >= minimumWindowSize && alpha > 0
    }

    private nonisolated static func cgWindowInfo() -> CGInfo {
        let all = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var entries: [WindowID: CGEntry] = [:]
        var pidsWithNormalWindows = Set<pid_t>()
        for (index, info) in all.enumerated() {
            guard let number = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            var bounds = CGRect.zero
            if let dictionary = info[kCGWindowBounds as String] as? NSDictionary {
                CGRectMakeWithDictionaryRepresentation(dictionary, &bounds)
            }
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            let pid = info[kCGWindowOwnerPID as String] as? pid_t
            let isNormal = isNormalCGWindow(layer: layer, bounds: bounds, alpha: alpha)
            entries[WindowID(Int(number))] = CGEntry(
                layer: layer, stackIndex: index, bounds: bounds, pid: pid ?? 0,
                title: info[kCGWindowName as String] as? String ?? "", isNormal: isNormal && pid != nil
            )
            if isNormal, let pid { pidsWithNormalWindows.insert(pid) }
        }
        let onScreenIDs = Set(onScreen.compactMap { ($0[kCGWindowNumber as String] as? CGWindowID).map { WindowID(Int($0)) } })
        return CGInfo(entries: entries, onScreenIDs: onScreenIDs, pidsWithNormalWindows: pidsWithNormalWindows)
    }

    /// Solo subrol estándar o diálogo, de al menos 100×100.
    private nonisolated static func isStandardWindow(_ element: AXUIElement) -> Bool {
        let subrole = axAttribute(element, kAXSubroleAttribute) as? String
        guard subrole == kAXStandardWindowSubrole as String || subrole == kAXDialogSubrole as String else { return false }
        var size = CGSize.zero
        if let value = axAttribute(element, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
            AXValueGetValue(value as! AXValue, .cgSize, &size)
        }
        return size.width >= minimumWindowSize && size.height >= minimumWindowSize
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
