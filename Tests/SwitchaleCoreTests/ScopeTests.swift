import Testing
import SwitchaleCore

@Suite("Scope")
struct ScopeTests {
    @Test("Hay exactamente dos Scopes: All Windows y Current App")
    func scopes() {
        #expect(Scope.allCases == [.allWindows, .currentApp])
    }
}
