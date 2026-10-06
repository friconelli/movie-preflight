import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let store = Store()
    func application(_ application: NSApplication, open urls: [URL]) { AppDelegate.store.add(urls) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
struct CollaudoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("Collaudo") { ContentView(store: AppDelegate.store) }
            .commands { CommandGroup(replacing: .newItem) { Button("Apri film…") { AppDelegate.store.open() }.keyboardShortcut("o") } }
    }
}
