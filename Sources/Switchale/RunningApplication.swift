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
}
