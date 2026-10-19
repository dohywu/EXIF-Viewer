import AppKit
import SwiftUI

/// Lets the app accept files from Finder ("열기 방식"), the Dock and the
/// command line, in addition to drag & drop.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var model: AppModel?
    private var pending: [URL] = []

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        deliver(urls)
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        deliver(urls)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        if !args.isEmpty { deliver(args.map { URL(fileURLWithPath: $0) }) }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func deliver(_ urls: [URL]) {
        pending += urls
        flush()
    }

    private func flush() {
        guard let model = AppDelegate.model else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.flush() }
            return
        }
        let urls = pending
        pending = []
        guard !urls.isEmpty else { return }
        Task { @MainActor in model.open(urls: urls) }
    }
}
