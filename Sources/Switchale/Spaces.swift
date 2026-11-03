import Darwin
import Foundation
import SwitchaleCore

// Único archivo que toca las APIs privadas de SkyLight (ADR-0002). Solo se usa con la opción
// "Windows de otros Spaces" activada: con la opción desactivada nadie llama a `Spaces`, y nada se
// resuelve ni se carga. Los símbolos se resuelven con `dlsym` (sin linkear SkyLight): si una
// versión de macOS los saca, `Spaces.isAvailable` es false y la app se comporta como con la opción
// desactivada.

enum Spaces {
    /// Si están todas las APIs privadas que hacen falta. Lo primero que se consulta antes de usar
    /// `Spaces`: la primera consulta carga SkyLight.
    static var isAvailable: Bool { symbols != nil }

    /// Ids de todas las ventanas de todos los Spaces (de todas las pantallas), o nil si SkyLight
    /// falló o no está.
    static func windowIDsInAllSpaces() -> Set<WindowID>? {
        guard let symbols else { return nil }
        let connection = symbols.mainConnectionID()
        guard let spaces = symbols.copySpaces(connection, allSpacesMask)?.takeRetainedValue(),
              CFArrayGetCount(spaces) > 0
        else { return nil }
        var setTags: UInt64 = 0
        var clearTags: UInt64 = 0
        guard let windows = symbols.copyWindowsWithOptionsAndTags(
            connection, 0, spaces, windowsOptions, &setTags, &clearTags
        )?.takeRetainedValue() as? [NSNumber]
        else { return nil }
        return Set(windows.map { WindowID($0.intValue) })
    }

    /// Pone al frente la App con esta Window como su Window key. macOS cambia al Space de la
    /// Window. Devuelve false si SkyLight falló o no está.
    static func focus(_ id: WindowID, pid: pid_t) -> Bool {
        guard let symbols else { return false }
        var psn = ProcessSerialNumber()
        guard symbols.getProcessForPID(pid, &psn) == noErr else { return false }
        let windowID = UInt32(truncatingIfNeeded: id.rawValue)
        guard symbols.setFrontProcessWithOptions(&psn, windowID, userGeneratedMode) == 0 else { return false }
        makeKeyWindow(windowID, of: &psn, symbols)
        return true
    }

    // MARK: - SkyLight

    /// `kCGSAllSpacesMask`: el Space actual y los otros, de todas las pantallas.
    private static let allSpacesMask: Int32 = 0b111
    /// Opción de `CGSCopyWindowsWithOptionsAndTags` que lista las ventanas de cada Space (no las
    /// que la App sacó de pantalla sin cerrarlas).
    private static let windowsOptions: Int32 = 2
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

    /// Hace key a la Window dentro de su App: los dos eventos sintéticos que manda el Window
    /// Server al hacer clic en ella.
    private static func makeKeyWindow(_ windowID: UInt32, of psn: inout ProcessSerialNumber, _ symbols: Symbols) {
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: windowID) { id in
            for (offset, byte) in id.enumerated() { bytes[0x3c + offset] = byte }
        }
        for offset in 0x20..<0x30 { bytes[offset] = 0xff }
        bytes[0x08] = 0x01
        _ = symbols.postEventRecordTo(&psn, &bytes)
        bytes[0x08] = 0x02
        _ = symbols.postEventRecordTo(&psn, &bytes)
    }
}
