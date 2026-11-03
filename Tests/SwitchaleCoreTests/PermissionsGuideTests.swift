import Testing
import SwitchaleCore

@Suite("Guía de permisos")
struct PermissionsGuideTests {
    @Test("Si falta algún permiso, la ventana de permisos aparece al arrancar")
    func showsWindowWhenSomethingIsMissing() {
        #expect(PermissionsGuide(PermissionsState(accessibility: false, screenRecording: true)).showsWindowAtLaunch)
        #expect(PermissionsGuide(PermissionsState(accessibility: true, screenRecording: false)).showsWindowAtLaunch)
        #expect(PermissionsGuide(PermissionsState(accessibility: false, screenRecording: false)).showsWindowAtLaunch)
    }

    @Test("Con todos los permisos otorgados, la ventana no aparece al arrancar")
    func noWindowWhenAllGranted() {
        #expect(!PermissionsGuide(PermissionsState(accessibility: true, screenRecording: true)).showsWindowAtLaunch)
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
            == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        #expect(Permission.screenRecording.settingsURL
            == "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    @Test("Sin Grabación de pantalla, la ventana aclara que el switcher funciona igual con ícono y título")
    func screenRecordingMissingExplainsFallback() {
        let rows = PermissionsGuide(PermissionsState(accessibility: true, screenRecording: false)).rows
        let screenRecording = rows[1]
        #expect(screenRecording.note
            == "El switcher funciona igual: muestra el ícono de la App y el título en lugar de la Thumbnail.")
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
