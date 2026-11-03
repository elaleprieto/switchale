import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private let orchestrator = Orchestrator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()
        orchestrator.start()
    }
}
