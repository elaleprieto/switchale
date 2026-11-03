import Testing
import SwitchaleCore

/// El Recency Order se observa por la Window que activaría un Quick Switch (la segunda del orden).
@Suite("Recency Order")
struct RecencyOrderTests {
    @Test("Sigue los cambios de foco externos")
    func externalFocus() {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        _ = c.send(.windowFocused(WindowID(3)))
        #expect(quickSwitchTarget(&c) == WindowID(1))
    }

    @Test("Las Windows que no vio recibir foco van al final, en orden de apilamiento")
    func unknownAtEnd() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        _ = c.send(.windowFocused(WindowID(2)))
        // Aparecen 4 (apilada detrás) y 3 (apilada delante): el orden queda 2, 1, 3, 4.
        _ = c.send(.snapshot(snapshot([win(1, stack: 2), win(2, stack: 3), win(3, stack: 0), win(4, stack: 1)])))
        #expect(quickSwitchTarget(&c) == WindowID(1))
        // Tras enfocar 1 el orden es 1, 2, 3, 4; enfocar 2 y 3 deja 3, 2, 1, 4.
        _ = c.send(.windowFocused(WindowID(1)))
        _ = c.send(.windowFocused(WindowID(2)))
        _ = c.send(.windowFocused(WindowID(3)))
        _ = c.send(.windowFocused(WindowID(4)))
        // Orden: 4, 3, 2, 1
        #expect(quickSwitchTarget(&c) == WindowID(3))
    }

    @Test("Una Window desconocida nunca pasa delante de las que recibieron foco")
    func unknownBehindFocused() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        _ = c.send(.windowFocused(WindowID(2)))
        _ = c.send(.snapshot(snapshot([win(1, stack: 1), win(2, stack: 2), win(3, stack: 0)])))
        #expect(quickSwitchTarget(&c) == WindowID(1))
    }

    @Test("Sin foco previo, el orden inicial es el de apilamiento")
    func initialStacking() {
        var c = core([win(7, stack: 1), win(5, stack: 0), win(9, stack: 2)])
        #expect(quickSwitchTarget(&c) == WindowID(7))
    }

    @Test("Las Windows cerradas salen del Recency Order")
    func closed() {
        var c = core([win(1, stack: 0), win(2, stack: 1), win(3, stack: 2)])
        _ = c.send(.snapshot(snapshot([win(1, stack: 0), win(3, stack: 1)])))
        #expect(quickSwitchTarget(&c) == WindowID(3))
    }
}
