import Darwin
import Foundation
import SwitchaleCore

// Único archivo que toca las APIs privadas de SkyLight (ADR-0002). Solo se usa con la opción
// "Windows de otros Spaces" activada: con la opción desactivada nadie llama a `Spaces`, y nada se
// resuelve ni se carga. Los símbolos se resuelven con `dlsym` (sin linkear SkyLight): si una
// versión de macOS los saca, o una llamada falla, `Spaces` no ubica las Windows de otros Spaces y
// la app se comporta como con la opción desactivada.

enum Spaces {
    /// Ids de las ventanas que están en otros Spaces y no en el actual (de ninguna pantalla), o nil
    /// si SkyLight falló o no está. La primera consulta carga SkyLight.
    static func windowIDsInOtherSpaces() -> Set<WindowID>? {
        guard let symbols,
              let all = windowIDs(inSpaces: allSpacesMask, symbols),
              let current = windowIDs(inSpaces: currentSpacesMask, symbols)
        else { return nil }
        return all.subtracting(current)
    }

    /// Pone al frente la App de la Window con ella como su Window key. macOS cambia al Space de la
    /// Window. Devuelve false si SkyLight falló o no está.
    static func focus(_ handle: WindowHandle) -> Bool {
        guard let symbols else { return false }
        var psn = ProcessSerialNumber()
        guard symbols.getProcessForPID(handle.app.processIdentifier, &psn) == noErr else { return false }
        let windowID = UInt32(truncatingIfNeeded: handle.id.rawValue)
        guard symbols.setFrontProcessWithOptions(&psn, windowID, userGeneratedMode) == 0 else { return false }
        makeKeyWindow(windowID, of: &psn, symbols)
        return true
    }

    // MARK: - SkyLight

    /// Máscaras de `CGSCopySpaces` (`kCGSSpaceIncludesCurrent`/`Others`/`User`).
    private static let includesCurrentSpaces: Int32 = 1 << 0
    private static let includesOtherSpaces: Int32 = 1 << 1
    private static let includesUserSpaces: Int32 = 1 << 2
    /// `kCGSAllSpacesMask`: el Space actual y los otros, de todas las pantallas.
    private static let allSpacesMask = includesCurrentSpaces | includesOtherSpaces | includesUserSpaces
    /// `kCGSCurrentSpaceMask`: el Space actual de cada pantalla.
    private static let currentSpacesMask = includesCurrentSpaces | includesUserSpaces
    /// Opción de `CGSCopyWindowsWithOptionsAndTags` que lista las ventanas de cada Space (no las
    /// que la App sacó de pantalla sin cerrarlas).
    private static let excludesOrderedOutWindowsOption: Int32 = 1 << 1
    /// `kCPSUserGenerated`: la activación la pidió el usuario.
    private static let userGeneratedMode: UInt32 = 0x200

    /// `ProcessSerialNumber` de Carbon, sin depender de la declaración deprecada.
    private struct ProcessSerialNumber {
        var highLongOfPSN: UInt32 = 0
        var lowLongOfPSN: UInt32 = 0
    }

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias CopySpaces = @convention(c) (Int32, Int32) -> Unmanaged<CFArray>?
    private typealias CopyWindowsWithOptionsAndTags = @convention(c) (
        Int32, Int32, CFArray, Int32, UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>
    ) -> Unmanaged<CFArray>?
    private typealias GetProcessForPID = @convention(c) (pid_t, UnsafeMutableRawPointer) -> OSStatus
    private typealias SetFrontProcessWithOptions = @convention(c) (
        UnsafeMutableRawPointer, UInt32, UInt32
    ) -> Int32
    private typealias PostEventRecordTo = @convention(c) (
        UnsafeMutableRawPointer, UnsafeMutablePointer<UInt8>
    ) -> Int32

    private struct Symbols: @unchecked Sendable {
        let mainConnectionID: MainConnectionID
        let copySpaces: CopySpaces
        let copyWindowsWithOptionsAndTags: CopyWindowsWithOptionsAndTags
        let getProcessForPID: GetProcessForPID
        let setFrontProcessWithOptions: SetFrontProcessWithOptions
        let postEventRecordTo: PostEventRecordTo
    }

    /// Se resuelve una sola vez, la primera vez que se usa (con la opción activada).
    private static let symbols: Symbols? = {
        guard let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        else { return nil }
        // `GetProcessForPID` es pública (deprecada), de ApplicationServices, que la app ya linkea.
        let applicationServices = dlopen(
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY
        )
        func resolve<T>(_ handle: UnsafeMutableRawPointer?, _ names: [String], as _: T.Type) -> T? {
            guard let handle else { return nil }
            for name in names {
                if let symbol = dlsym(handle, name) { return unsafeBitCast(symbol, to: T.self) }
            }
            return nil
        }
        guard
            let mainConnectionID = resolve(skyLight, ["SLSMainConnectionID", "CGSMainConnectionID"], as: MainConnectionID.self),
            let copySpaces = resolve(skyLight, ["SLSCopySpaces", "CGSCopySpaces"], as: CopySpaces.self),
            let copyWindows = resolve(
                skyLight, ["SLSCopyWindowsWithOptionsAndTags", "CGSCopyWindowsWithOptionsAndTags"],
                as: CopyWindowsWithOptionsAndTags.self
            ),
            let getProcessForPID = resolve(applicationServices, ["GetProcessForPID"], as: GetProcessForPID.self),
            let setFront = resolve(skyLight, ["_SLPSSetFrontProcessWithOptions"], as: SetFrontProcessWithOptions.self),
            let postEvent = resolve(skyLight, ["SLPSPostEventRecordTo"], as: PostEventRecordTo.self)
        else { return nil }
        return Symbols(
            mainConnectionID: mainConnectionID, copySpaces: copySpaces, copyWindowsWithOptionsAndTags: copyWindows,
            getProcessForPID: getProcessForPID, setFrontProcessWithOptions: setFront, postEventRecordTo: postEvent
        )
    }()

    /// Ids de las ventanas de los Spaces de esta máscara, o nil si SkyLight falló.
    private static func windowIDs(inSpaces mask: Int32, _ symbols: Symbols) -> Set<WindowID>? {
        let connection = symbols.mainConnectionID()
        guard let spaces = symbols.copySpaces(connection, mask)?.takeRetainedValue(),
              CFArrayGetCount(spaces) > 0
        else { return nil }
        var setTags: UInt64 = 0
        var clearTags: UInt64 = 0
        guard let windows = symbols.copyWindowsWithOptionsAndTags(
            connection, 0, spaces, excludesOrderedOutWindowsOption, &setTags, &clearTags
        )?.takeRetainedValue() as? [NSNumber]
        else { return nil }
        return Set(windows.map { WindowID($0.intValue) })
    }

    /// Registro de evento del Window Server que espera `SLPSPostEventRecordTo` (sin documentar).
    private enum EventRecord {
        static let size = 0xf8
        /// Byte con el tamaño del registro.
        static let sizeOffset = 0x04
        /// Byte con el tipo de evento.
        static let typeOffset = 0x08
        static let mouseDown: UInt8 = 0x01
        static let mouseUp: UInt8 = 0x02
        /// Bytes de la máscara del evento, todos en 1.
        static let maskRange = 0x20..<0x30
        /// Byte de flags: el evento va a una Window concreta.
        static let flagsOffset = 0x3a
        static let targetsWindowFlag: UInt8 = 0x10
        /// Dónde empieza el id de la Window (4 bytes).
        static let windowIDOffset = 0x3c
    }

    /// Hace key a la Window dentro de su App: los dos eventos sintéticos que manda el Window
    /// Server al hacer clic en ella.
    private static func makeKeyWindow(_ windowID: UInt32, of psn: inout ProcessSerialNumber, _ symbols: Symbols) {
        var bytes = [UInt8](repeating: 0, count: EventRecord.size)
        bytes[EventRecord.sizeOffset] = UInt8(EventRecord.size)
        bytes[EventRecord.flagsOffset] = EventRecord.targetsWindowFlag
        withUnsafeBytes(of: windowID) { id in
            for (offset, byte) in id.enumerated() { bytes[EventRecord.windowIDOffset + offset] = byte }
        }
        for offset in EventRecord.maskRange { bytes[offset] = 0xff }
        bytes[EventRecord.typeOffset] = EventRecord.mouseDown
        _ = symbols.postEventRecordTo(&psn, &bytes)
        bytes[EventRecord.typeOffset] = EventRecord.mouseUp
        _ = symbols.postEventRecordTo(&psn, &bytes)
    }
}
