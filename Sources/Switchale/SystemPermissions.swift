import AppKit
import ApplicationServices
import SwitchaleCore

/// Adaptador de los permisos de TCC: consulta su estado sin pedirlos y, a pedido
/// del usuario, los solicita y abre el panel de Configuración del Sistema.
@MainActor
protocol PermissionsProvider {
    /// Estado actual, sin mostrar ningún diálogo.
    func current() -> PermissionsState
    /// Lleva al usuario a otorgar `permission`.
    func requestAccess(to permission: Permission)
}

@MainActor
struct SystemPermissions: PermissionsProvider {
    func current() -> PermissionsState {
        PermissionsState(
            accessibility: AXIsProcessTrusted(),
            screenRecording: CGPreflightScreenCaptureAccess()
        )
    }

    func requestAccess(to permission: Permission) {
        // Pedir el permiso agrega switchale a la lista del panel; si no, el
        // usuario tendría que buscar la app con "+".
        switch permission {
        case .accessibility:
            // "AXTrustedCheckOptionPrompt" es el valor de kAXTrustedCheckOptionPrompt
            // (una global no Sendable en Swift 6).
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        }
        if let url = URL(string: permission.settingsURL) {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Consulta periódicamente los permisos y avisa cuando cambian, así la ventana y
/// el menú se actualizan sin reiniciar la app (macOS no notifica estos cambios).
@MainActor
final class PermissionsMonitor {
    private let provider: PermissionsProvider
    private let onChange: (PermissionsState) -> Void
    private var timer: Timer?
    private(set) var state: PermissionsState

    init(provider: PermissionsProvider, onChange: @escaping (PermissionsState) -> Void) {
        self.provider = provider
        self.onChange = onChange
        self.state = provider.current()
    }

    func start(interval: TimeInterval = 1) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        let latest = provider.current()
        guard latest != state else { return }
        state = latest
        onChange(latest)
    }
}
