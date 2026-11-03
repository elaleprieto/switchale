import Testing
import SwitchaleCore

@Suite("Iniciar al loguearse")
struct LaunchAtLoginTests {
    @Test("Por defecto switchale se inicia al loguearse")
    func enabledByDefault() {
        #expect(LaunchAtLogin.enabledByDefault)
    }

    @Test("Si el usuario lo quiere y no está registrado, se registra el login item",
          arguments: [LoginItemStatus.notRegistered, .notFound])
    func registersWhenMissing(status: LoginItemStatus) {
        #expect(LaunchAtLogin.action(wanted: true, status: status) == .register)
    }

    @Test("Si ya está registrado, no se hace nada")
    func nothingWhenAlreadyRegistered() {
        #expect(LaunchAtLogin.action(wanted: true, status: .enabled) == nil)
    }

    @Test("Si macOS espera la aprobación del usuario, no se vuelve a registrar")
    func nothingWhenAwaitingApproval() {
        #expect(LaunchAtLogin.action(wanted: true, status: .requiresApproval) == nil)
    }

    @Test("Si el usuario lo desactivó y está registrado, se desregistra",
          arguments: [LoginItemStatus.enabled, .requiresApproval])
    func unregistersWhenUnwanted(status: LoginItemStatus) {
        #expect(LaunchAtLogin.action(wanted: false, status: status) == .unregister)
    }

    @Test("Si el usuario lo desactivó y no está registrado, no se hace nada",
          arguments: [LoginItemStatus.notRegistered, .notFound])
    func nothingWhenUnwantedAndMissing(status: LoginItemStatus) {
        #expect(LaunchAtLogin.action(wanted: false, status: status) == nil)
    }
}
