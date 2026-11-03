import AppKit

extension NSRunningApplication {
    /// switchale misma.
    var isSwitchale: Bool { processIdentifier == ProcessInfo.processInfo.processIdentifier }

    /// Si sus Windows entran en el Window Switcher: las Apps regulares, y switchale aunque no tenga
    /// ícono en el Dock (`LSUIElement`): sus Windows (Preferencias, permisos) son Windows como
    /// cualquier otra, también para Current App.
    var listsWindowsInSwitcher: Bool {
        activationPolicy == .regular || isSwitchale
    }

    /// Si puede entrar como Windowless App cuando no tiene Windows. Finder y switchale no: corren
    /// siempre, y switchale sin Windows no tiene nada que mostrar al activarla.
    var canBeWindowless: Bool {
        !isSwitchale && bundleIdentifier != "com.apple.finder"
    }
}
