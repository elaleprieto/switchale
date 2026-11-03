import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Sin ícono en el Dock (refuerza LSUIElement del Info.plist).
app.setActivationPolicy(.accessory)
app.run()
