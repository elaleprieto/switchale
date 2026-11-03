import AppKit
import ApplicationServices
import SwitchaleCore

/// Traduce cambios de foco (AX por App y NSWorkspace) en "una Window recibió foco" y
/// "pasó a ser la App activa", y avisa cuando cambia el conjunto de Apps para refrescar la foto.
///
/// Para switchale misma no se usa AX: una consulta AX al propio proceso desde el main thread no
/// puede responderse mientras el main thread espera, y bloquea hasta el timeout. Sus Windows
/// enfocadas salen de AppKit (`keyWindow` y `NSWindow.didBecomeKeyNotification`).
@MainActor
final class FocusTracker {
    private var observers: [pid_t: AXObserver] = [:]
    private var tokens: [NSObjectProtocol] = []
    private var retryTimer: Timer?
    private let onFocus: (WindowID) -> Void
    private let onAppActivated: (AppID) -> Void
    private let onAppsChanged: () -> Void

    init(
        onFocus: @escaping (WindowID) -> Void,
        onAppActivated: @escaping (AppID) -> Void,
        onAppsChanged: @escaping () -> Void
    ) {
        self.onFocus = onFocus
        self.onAppActivated = onAppActivated
        self.onAppsChanged = onAppsChanged
    }

    func start() {
        observeAllApps()

        observeWorkspace(NSWorkspace.didLaunchApplicationNotification) { [weak self] app in
            self?.observe(app)
            self?.onAppsChanged()
        }
        observeWorkspace(NSWorkspace.didTerminateApplicationNotification) { [weak self] app in
            self?.forget(app.processIdentifier)
            self?.onAppsChanged()
        }
        observeWorkspace(NSWorkspace.didActivateApplicationNotification) { [weak self] app in
            self?.reportActivation(of: app)
        }
        observeWorkspace(NSWorkspace.didHideApplicationNotification) { [weak self] _ in self?.onAppsChanged() }
        observeWorkspace(NSWorkspace.didUnhideApplicationNotification) { [weak self] _ in self?.onAppsChanged() }
        observeOwnKeyWindow()
    }

    /// Informa que la App pasó a ser la activa (incluida switchale) y su Window enfocada, si tiene.
    func reportActivation(of app: NSRunningApplication) {
        onAppActivated(AppID(Int(app.processIdentifier)))
        if app.isSwitchale {
            if let window = NSApp.keyWindow { reportOwnFocus(window) }
        } else {
            reportFocusedWindow(pid: app.processIdentifier)
        }
    }

    /// Informa la Window enfocada de la App (si hay una). Nunca para switchale: ver arriba.
    func reportFocusedWindow(pid: pid_t) {
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        guard let id = axFocusedWindowID(pid: pid) else { return }
        onFocus(id)
    }

    private func observeWorkspace(_ name: Notification.Name, _ handler: @escaping @MainActor (NSRunningApplication) -> Void) {
        let token = NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { handler(app) }
        }
        tokens.append(token)
    }

    /// Una Window de switchale pasa a ser la key window con switchale activa.
    private func observeOwnKeyWindow() {
        let token = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                guard NSApp.isActive else { return }
                self?.reportOwnFocus(window)
            }
        }
        tokens.append(token)
    }

    /// El número de una NSWindow es su CGWindowID, el mismo id que tiene en la foto.
    private func reportOwnFocus(_ window: NSWindow) {
        guard window.windowNumber > 0 else { return }
        onFocus(WindowID(window.windowNumber))
    }

    private func observeAllApps() {
        for app in NSWorkspace.shared.runningApplications where app.listsWindowsInSwitcher && !app.isSwitchale {
            observe(app)
        }
    }

    /// Registra el observer de AX de la App. Si falla (p. ej. sin Accesibilidad) no deja nada
    /// registrado y se reintenta cuando haya Accesibilidad.
    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard observers[pid] == nil, !app.isSwitchale else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, focusCallback, &created) == .success, let observer = created else {
            scheduleRetryIfNeeded()
            return
        }
        let appElement = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(observer, appElement, kAXFocusedWindowChangedNotification as CFString, context) == .success else {
            scheduleRetryIfNeeded()
            return
        }
        // La notificación de Window principal es complementaria: si falla no invalida el observer.
        _ = AXObserverAddNotification(observer, appElement, kAXMainWindowChangedNotification as CFString, context)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func scheduleRetryIfNeeded() {
        guard retryTimer == nil, !AXIsProcessTrusted() else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, AXIsProcessTrusted() else { return }
                self.retryTimer?.invalidate()
                self.retryTimer = nil
                self.observeAllApps()
                self.onAppsChanged()
            }
        }
    }

    private func forget(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
}

private func focusCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let tracker = Unmanaged<FocusTracker>.fromOpaque(context).takeUnretainedValue()
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success else { return }
    MainActor.assumeIsolated { tracker.reportFocusedWindow(pid: pid) }
}
