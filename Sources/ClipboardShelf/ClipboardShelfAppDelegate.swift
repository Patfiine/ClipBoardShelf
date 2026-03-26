import AppKit

@MainActor
final class ClipboardShelfAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ClipboardCenter.shared.configureApplication()
    }
}
