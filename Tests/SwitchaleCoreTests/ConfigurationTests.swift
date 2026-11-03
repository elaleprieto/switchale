import Testing
import SwitchaleCore

@Suite("Configuración por defecto")
struct ConfigurationTests {
    @Test("All Windows usa ⌘⇥, Current App usa ⌥` y el Activation Delay es 80 ms")
    func defaults() {
        let config = Configuration.default

        #expect(config.allWindows == ScopeSettings(isEnabled: true, hotkey: Hotkey(modifier: .command, key: .tab)))
        #expect(config.currentApp == ScopeSettings(isEnabled: true, hotkey: Hotkey(modifier: .option, key: .backtick)))
        #expect(config.activationDelayMilliseconds == 80)
    }
}
