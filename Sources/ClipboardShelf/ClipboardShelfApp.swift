import SwiftUI

@main
struct ClipboardShelfApp: App {
    @NSApplicationDelegateAdaptor(ClipboardShelfAppDelegate.self) private var appDelegate
    @StateObject private var center = ClipboardCenter.shared

    var body: some Scene {
        Settings {
            SettingsView(center: center)
                .frame(width: 420, height: 260)
        }
    }
}
