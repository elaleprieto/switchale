// Núcleo del switcher: Swift puro, sin AppKit, AX ni CoreGraphics.

/// Qué permisos de macOS tiene otorgados switchale en un momento dado.
public struct PermissionsState: Sendable, Equatable {
    /// Accesibilidad: obligatorio para el event tap y para activar Windows.
    public var accessibility: Bool
    /// Grabación de pantalla: solo para las Thumbnails.
    public var screenRecording: Bool

    public init(accessibility: Bool, screenRecording: Bool) {
        self.accessibility = accessibility
        self.screenRecording = screenRecording
    }
}

/// Un permiso de macOS que necesita switchale.
public enum Permission: Sendable, CaseIterable {
    case accessibility
    case screenRecording

    /// URL del panel de Configuración del Sistema donde se otorga.
    public var settingsURL: String {
        switch self {
        case .accessibility:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .screenRecording:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
    }
}

extension PermissionsState {
    public func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility: accessibility
        case .screenRecording: screenRecording
        }
    }
}

/// Lo que muestra la ventana de permisos para un permiso.
public struct PermissionRow: Sendable, Equatable {
    public let permission: Permission
    public let title: String
    public let isGranted: Bool
    public let statusText: String
    /// Aclaración sobre qué pasa sin el permiso; `nil` si está otorgado.
    public let note: String?
}

/// Qué mostrar al usuario según el estado de los permisos.
public struct PermissionsGuide: Sendable, Equatable {
    public let state: PermissionsState

    public init(_ state: PermissionsState) {
        self.state = state
    }

    /// Si al arrancar hay que abrir la ventana de permisos.
    public var showsWindowAtLaunch: Bool {
        !state.accessibility || !state.screenRecording
    }

    /// Aviso para el menú de la barra. Solo avisa la falta de Accesibilidad:
    /// sin ella switchale no puede reemplazar ⌘⇥.
    public var menuWarning: String? {
        state.accessibility ? nil : "Falta el permiso de Accesibilidad"
    }

    /// Una fila por permiso para la ventana de permisos, Accesibilidad primero.
    public var rows: [PermissionRow] {
        Permission.allCases.map { permission in
            let granted = state.isGranted(permission)
            return PermissionRow(
                permission: permission,
                title: Self.title(permission),
                isGranted: granted,
                statusText: granted ? "Otorgado" : "Sin otorgar",
                note: granted ? nil : Self.missingNote(permission)
            )
        }
    }

    private static func title(_ permission: Permission) -> String {
        switch permission {
        case .accessibility: "Accesibilidad"
        case .screenRecording: "Grabación de pantalla"
        }
    }

    private static func missingNote(_ permission: Permission) -> String {
        switch permission {
        case .accessibility:
            "Obligatorio. Sin este permiso ⌘⇥ sigue mostrando el App Switcher de macOS."
        case .screenRecording:
            "El switcher funciona igual: muestra el ícono de la App y el título en lugar de la Thumbnail."
        }
    }
}
