// Núcleo del Window Switcher: Swift puro, sin AppKit, AX ni CoreGraphics.

import Foundation

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

    public func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility: accessibility
        case .screenRecording: screenRecording
        }
    }
}

/// Un permiso de macOS que necesita switchale.
public enum Permission: Sendable, CaseIterable {
    case accessibility
    case screenRecording

    /// Todo lo que switchale sabe de un permiso, en un solo lugar.
    struct Details {
        let title: String
        /// Aclaración sobre qué pasa sin el permiso.
        let missingNote: String
        /// Panel de Configuración del Sistema donde se otorga.
        let settingsURL: URL
        /// Sin un permiso obligatorio switchale no puede reemplazar ⌘⇥.
        let isRequired: Bool
        /// Si macOS informa el permiso recién otorgado sin reabrir la app.
        let refreshesLive: Bool
    }

    var details: Details {
        switch self {
        case .accessibility:
            Details(
                title: "Accesibilidad",
                missingNote: "Obligatorio. Sin este permiso ⌘⇥ sigue mostrando el App Switcher de macOS.",
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!,
                isRequired: true,
                refreshesLive: true
            )
        case .screenRecording:
            Details(
                title: "Grabación de pantalla",
                missingNote: "El Window Switcher funciona igual: muestra el ícono de la App y el título en lugar de la Thumbnail.",
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!,
                isRequired: false,
                // CGPreflightScreenCaptureAccess puede seguir en false hasta reabrir.
                refreshesLive: false
            )
        }
    }

    public var title: String { details.title }

    /// URL del panel de Configuración del Sistema donde se otorga.
    public var settingsURL: URL { details.settingsURL }
}

/// Lo que muestra la ventana de permisos para un permiso.
public struct PermissionRow: Sendable, Equatable {
    public let permission: Permission
    public let title: String
    public let isGranted: Bool
    public let statusText: String
    /// Aclaración sobre qué pasa sin el permiso; `nil` si está otorgado.
    public let note: String?
    /// Qué hace el botón de la fila; `nil` si está otorgado (no hay botón).
    public let action: PermissionAction?
    /// Si no `nil`, la fila sugiere reabrir switchale (con un botón) porque el
    /// permiso ya se pidió y macOS puede no informarlo hasta reabrir la app.
    public let relaunchHint: String?
}

/// Qué hace el botón de un permiso faltante.
public enum PermissionAction: Sendable, Equatable {
    /// Pide el permiso: diálogo del sistema y alta de switchale en la lista del panel.
    case request
    /// Abre el panel de Configuración del Sistema del permiso.
    case openSettings
}

/// Qué mostrar al usuario según el estado de los permisos.
public struct PermissionsGuide: Sendable, Equatable {
    public let state: PermissionsState
    /// Permisos que switchale ya pidió alguna vez.
    public let requested: Set<Permission>
    /// Si es la primera vez que arranca switchale.
    public let isFirstLaunch: Bool

    public init(_ state: PermissionsState, requested: Set<Permission> = [], isFirstLaunch: Bool = false) {
        self.state = state
        self.requested = requested
        self.isFirstLaunch = isFirstLaunch
    }

    /// Si al arrancar hay que abrir la ventana de permisos: siempre que falte uno
    /// obligatorio; por uno opcional, solo en el primer arranque.
    public var showsWindowAtLaunch: Bool {
        Permission.allCases.contains { permission in
            !state.isGranted(permission) && (permission.details.isRequired || isFirstLaunch)
        }
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
            let wasRequested = requested.contains(permission)
            return PermissionRow(
                permission: permission,
                title: permission.title,
                isGranted: granted,
                statusText: granted ? "Otorgado" : "Sin otorgar",
                note: granted ? nil : permission.details.missingNote,
                action: granted ? nil : wasRequested ? .openSettings : .request,
                relaunchHint: !granted && wasRequested && !permission.details.refreshesLive
                    ? "Si ya lo otorgaste, reabrí switchale para que lo detecte."
                    : nil
            )
        }
    }
}
