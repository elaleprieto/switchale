import Foundation
import SwitchaleCore

extension AppID {
    /// El adaptador identifica cada App por su pid.
    var pid: pid_t { pid_t(rawValue) }
}

extension AppID {
    init(pid: pid_t) { self.init(Int(pid)) }
}
