import AppKit
import ApplicationServices
import SwitchaleCore

/// Adaptador de los permisos de TCC: consulta su estado sin pedirlos, los pide y
/// abre el panel de Configuración del Sistema. Qué hacer en cada caso lo decide
/// el núcleo (`PermissionsGuide`).
@MainActor
enum SystemPermissions {
    /// Estado actual, sin mostrar ningún diálogo.
    static func current() -> PermissionsState {
        PermissionsState(
            accessibility: AXIsProcessTrusted(),
            screenRecording: CGPreflightScreenCaptureAccess()
        )
    }

    /// Pide `permission`: muestra el diálogo del sistema y agrega switchale a la
    /// lista del panel (si no, el usuario tendría que buscar la app con "+").
    static func request(_ permission: Permission) {
        switch permission {
        case .accessibility:
            // "AXTrustedCheckOptionPrompt" es el valor de kAXTrustedCheckOptionPrompt
            // (una global no Sendable en Swift 6).
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        }
    }

    /// Abre el panel de Configuración del Sistema donde se otorga `permission`.
    static func openSettings(for permission: Permission) {
        NSWorkspace.shared.open(permission.settingsURL)
    }
}
