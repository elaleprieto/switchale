import AppKit
import SwitchaleCore

extension ScreenID {
    init(display: CGDirectDisplayID) {
        self.init(Int(display))
    }
}

extension NSScreen {
    /// El `ScreenID` de esta pantalla; la única conversión de `NSScreen` a `ScreenID`.
    var screenID: ScreenID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { ScreenID(display: $0.uint32Value) }
    }
}
