// Núcleo del switcher: Swift puro, sin AppKit, AX ni CoreGraphics.

/// Estado del login item según macOS (espejo de `SMAppService.Status`).
public enum LoginItemStatus: Sendable, Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

/// Qué hacer con el login item para que coincida con lo que quiere el usuario.
public enum LoginItemAction: Sendable, Equatable {
    case register
    case unregister
}

/// Inicio de switchale al loguearse.
public enum LaunchAtLogin {
    /// Valor por defecto de la preferencia "iniciar al loguearse".
    public static let enabledByDefault = true

    /// La acción necesaria para pasar de `status` a lo que el usuario quiere,
    /// o `nil` si no hay nada que hacer. Si macOS espera la aprobación del
    /// usuario (`requiresApproval`), el registro ya está hecho: no se repite.
    public static func action(wanted: Bool, status: LoginItemStatus) -> LoginItemAction? {
        switch (wanted, status) {
        case (true, .notRegistered), (true, .notFound): .register
        case (false, .enabled), (false, .requiresApproval): .unregister
        default: nil
        }
    }
}
