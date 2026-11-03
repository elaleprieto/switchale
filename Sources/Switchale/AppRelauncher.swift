import AppKit

/// Reabre switchale: lanza una instancia nueva del bundle (como `open -n`) y
/// cierra esta. Sirve para que macOS informe un permiso de Grabación de pantalla
/// recién otorgado, que `CGPreflightScreenCaptureAccess` no refresca en vivo.
@MainActor
enum AppRelauncher {
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    NSLog("switchale: no se pudo reabrir: \(error)")
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }
}
