import Foundation
import Testing
import SwitchaleCore

@Suite("Guía de permisos")
struct PermissionsGuideTests {
    @Test("Si falta Accesibilidad, la ventana de permisos aparece en cada arranque")
    func showsWindowWhenAccessibilityIsMissing() {
        for isFirstLaunch in [true, false] {
            #expect(PermissionsGuide(
                PermissionsState(accessibility: false, screenRecording: true), isFirstLaunch: isFirstLaunch
            ).showsWindowAtLaunch)
            #expect(PermissionsGuide(
                PermissionsState(accessibility: false, screenRecording: false), isFirstLaunch: isFirstLaunch
            ).showsWindowAtLaunch)
        }
    }

    @Test("Si solo falta Grabación de pantalla, la ventana aparece solo en el primer arranque")
    func showsWindowForScreenRecordingOnlyOnFirstLaunch() {
        let state = PermissionsState(accessibility: true, screenRecording: false)
        #expect(PermissionsGuide(state, isFirstLaunch: true).showsWindowAtLaunch)
        #expect(!PermissionsGuide(state, isFirstLaunch: false).showsWindowAtLaunch)
    }

    @Test("Con todos los permisos otorgados, la ventana no aparece al arrancar")
    func noWindowWhenAllGranted() {
        let state = PermissionsState(accessibility: true, screenRecording: true)
        #expect(!PermissionsGuide(state, isFirstLaunch: true).showsWindowAtLaunch)
        #expect(!PermissionsGuide(state, isFirstLaunch: false).showsWindowAtLaunch)
    }

    @Test("Si falta Accesibilidad, el menú de la barra lo avisa")
    func menuWarnsWithoutAccessibility() {
        let guide = PermissionsGuide(PermissionsState(accessibility: false, screenRecording: true))
        #expect(guide.menuWarning == "Falta el permiso de Accesibilidad")
    }

    @Test("Sin Grabación de pantalla pero con Accesibilidad, el menú no avisa nada")
    func menuDoesNotWarnForScreenRecordingOnly() {
        #expect(PermissionsGuide(PermissionsState(accessibility: true, screenRecording: false)).menuWarning == nil)
        #expect(PermissionsGuide(PermissionsState(accessibility: true, screenRecording: true)).menuWarning == nil)
    }

    @Test("La ventana muestra una fila por permiso, Accesibilidad primero, con su estado")
    func rowsShowEachPermissionStatus() {
        let rows = PermissionsGuide(PermissionsState(accessibility: true, screenRecording: false)).rows
        #expect(rows.map(\.permission) == [.accessibility, .screenRecording])
        #expect(rows.map(\.title) == ["Accesibilidad", "Grabación de pantalla"])
        #expect(rows.map(\.isGranted) == [true, false])
        #expect(rows.map(\.statusText) == ["Otorgado", "Sin otorgar"])
    }

    @Test("Cada permiso abre su propio panel de Configuración del Sistema")
    func eachPermissionOpensItsSettingsPane() {
        #expect(Permission.accessibility.settingsURL
            == URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"))
        #expect(Permission.screenRecording.settingsURL
            == URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"))
    }

    @Test("Sin Grabación de pantalla, la ventana aclara que el Window Switcher funciona igual con ícono y título")
    func screenRecordingMissingExplainsFallback() {
        let rows = PermissionsGuide(PermissionsState(accessibility: true, screenRecording: false)).rows
        let screenRecording = rows[1]
        #expect(screenRecording.note
            == "El Window Switcher funciona igual: muestra el ícono de la App y el título en lugar de la Thumbnail.")
    }

    @Test("Con Grabación de pantalla otorgada, no hace falta la aclaración")
    func screenRecordingGrantedHasNoNote() {
        let rows = PermissionsGuide(PermissionsState(accessibility: true, screenRecording: true)).rows
        #expect(rows[1].note == nil)
    }

    @Test("Sin Accesibilidad, la ventana aclara que ⌘⇥ sigue funcionando como siempre")
    func accessibilityMissingExplainsConsequence() {
        let rows = PermissionsGuide(PermissionsState(accessibility: false, screenRecording: true)).rows
        #expect(rows[0].note
            == "Obligatorio. Sin este permiso ⌘⇥ sigue mostrando el App Switcher de macOS.")
        let granted = PermissionsGuide(PermissionsState(accessibility: true, screenRecording: true)).rows
        #expect(granted[0].note == nil)
    }
}

@Suite("Botón de cada permiso")
struct PermissionButtonTests {
    @Test("Si el permiso nunca se pidió, el botón lo pide (sin abrir el panel)")
    func firstClickRequests() {
        let rows = PermissionsGuide(PermissionsState(accessibility: false, screenRecording: false)).rows
        #expect(rows.map(\.action) == [.request, .request])
    }

    @Test("Si el permiso ya se pidió y sigue faltando, el botón abre el panel de Configuración del Sistema")
    func laterClicksOpenSettings() {
        let guide = PermissionsGuide(
            PermissionsState(accessibility: false, screenRecording: false),
            requested: [.accessibility]
        )
        #expect(guide.rows.map(\.action) == [.openSettings, .request])
    }

    @Test("Con el permiso otorgado no hay botón")
    func grantedHasNoButton() {
        let guide = PermissionsGuide(
            PermissionsState(accessibility: true, screenRecording: true),
            requested: [.accessibility]
        )
        #expect(guide.rows.map(\.action) == [nil, nil])
    }
}

@Suite("Grabación de pantalla sin reiniciar")
struct RelaunchHintTests {
    @Test("Si Grabación de pantalla ya se pidió y sigue faltando, la fila ofrece reabrir switchale")
    func requestedScreenRecordingOffersRelaunch() {
        let guide = PermissionsGuide(
            PermissionsState(accessibility: true, screenRecording: false),
            requested: [.screenRecording]
        )
        #expect(guide.rows[1].relaunchHint == "Si ya lo otorgaste, reabrí switchale para que lo detecte.")
    }

    @Test("Si Grabación de pantalla nunca se pidió, no ofrece reabrir")
    func unrequestedScreenRecordingDoesNotOfferRelaunch() {
        let guide = PermissionsGuide(PermissionsState(accessibility: true, screenRecording: false))
        #expect(guide.rows[1].relaunchHint == nil)
    }

    @Test("Con Grabación de pantalla otorgada, no ofrece reabrir")
    func grantedScreenRecordingDoesNotOfferRelaunch() {
        let guide = PermissionsGuide(
            PermissionsState(accessibility: true, screenRecording: true),
            requested: [.screenRecording]
        )
        #expect(guide.rows[1].relaunchHint == nil)
    }

    @Test("Accesibilidad se detecta en vivo: nunca ofrece reabrir")
    func accessibilityNeverOffersRelaunch() {
        let guide = PermissionsGuide(
            PermissionsState(accessibility: false, screenRecording: true),
            requested: [.accessibility]
        )
        #expect(guide.rows[0].relaunchHint == nil)
    }
}
