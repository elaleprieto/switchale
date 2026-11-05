import Testing
@testable import SwitchaleCore

/// Las Windows abiertas arriba; las Minimized Windows y las Windowless Apps abajo, desde una fila
/// nueva y separadas por una línea.
@Suite("Window Switcher: secciones")
struct SectionsTests {
    @Test("Con Windows abiertas y Minimized, la sección de abajo empieza en la primera Minimized")
    func breakAtFirstMinimized() {
        var c = core([win(1, stack: 0), win(2, stack: 1, minimized: true), win(3, stack: 2)])
        #expect(shownContent(holdHotkey(&c))?.lowerSectionStart == 2)
    }

    @Test("Las Windowless Apps van en la sección de abajo, aunque no haya Minimized Windows")
    func windowlessBelow() {
        var c = core([win(1, stack: 0), win(2, stack: 1)], windowless: [9])
        #expect(shownContent(holdHotkey(&c))?.lowerSectionStart == 2)
    }

    @Test("Sin Minimized Windows ni Windowless Apps no hay sección de abajo")
    func noLowerSection() {
        var c = core([win(1, stack: 0), win(2, stack: 1)])
        #expect(shownContent(holdHotkey(&c))?.lowerSectionStart == nil)
    }

    @Test("Si todas son Minimized no hay separación: es una sola sección")
    func allMinimized() {
        var c = core([win(1, stack: 0, minimized: true), win(2, stack: 1, minimized: true)])
        #expect(shownContent(holdHotkey(&c))?.lowerSectionStart == nil)
    }

    // Abiertas 1 2 3 4 y Minimized 5 6, en 3 columnas:
    //   0 1 2
    //   3
    //   ─────
    //   4 5
    private func sectionsSession(selected: Int) -> SwitcherCore {
        var c = core([
            win(1, stack: 0), win(2, stack: 1), win(3, stack: 2), win(4, stack: 3),
            win(5, stack: 4, minimized: true), win(6, stack: 5, minimized: true),
        ])
        holdHotkey(&c)
        _ = c.send(.switcherColumnsChanged(3))
        for _ in 0..<((selected - 1 + 6) % 6) { _ = c.send(.keyDown(.tab, [.command], isRepeat: false)) }
        return c
    }

    @Test("↓ desde la última fila de las abiertas va a la primera fila de abajo, en la misma columna")
    func downIntoLowerSection() {
        var c = sectionsSession(selected: 3)
        #expect(pressHoldingCommand(.downArrow, &c) == [.consumeEvent, .selectItem(4)])
    }

    @Test("↓ hacia una columna que no existe en la fila incompleta de las abiertas va a su último ítem")
    func downIntoIncompleteRow() {
        var c = sectionsSession(selected: 1)
        #expect(pressHoldingCommand(.downArrow, &c) == [.consumeEvent, .selectItem(3)])
    }

    @Test("↑ desde la sección de abajo hacia una columna que no existe arriba va al último ítem de esa fila")
    func upIntoIncompleteRow() {
        var c = sectionsSession(selected: 5)
        #expect(pressHoldingCommand(.upArrow, &c) == [.consumeEvent, .selectItem(3)])
    }

    @Test("↑ desde la primera columna de abajo sube a la fila de arriba")
    func upFromLowerSection() {
        var c = sectionsSession(selected: 4)
        #expect(pressHoldingCommand(.upArrow, &c) == [.consumeEvent, .selectItem(3)])
        #expect(pressHoldingCommand(.upArrow, &c) == [.consumeEvent, .selectItem(0)])
    }

    @Test("La grilla ubica la sección de abajo desde una fila nueva")
    func gridPositions() {
        let grid = SwitcherGrid(count: 6, lowerSectionStart: 4, columns: 3)
        #expect(grid.rowCount == 3)
        #expect(grid.position(of: 3) == SwitcherGrid.Position(row: 1, column: 0))
        #expect(grid.position(of: 4) == SwitcherGrid.Position(row: 2, column: 0))
        #expect(grid.position(of: 5) == SwitcherGrid.Position(row: 2, column: 1))
        #expect(grid.lowerSectionFirstRow == 2)
    }

    @Test("Sin sección de abajo la grilla llena las filas de corrido")
    func gridSingleSection() {
        let grid = SwitcherGrid(count: 7, lowerSectionStart: nil, columns: 3)
        #expect(grid.rowCount == 3)
        #expect(grid.position(of: 6) == SwitcherGrid.Position(row: 2, column: 0))
        #expect(grid.lowerSectionFirstRow == nil)
    }
}
