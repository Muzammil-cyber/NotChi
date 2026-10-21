import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var shared: AppDelegate?

    private var host: ModuleHost!
    private var controller: NotchController!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self

        let clipboard = ClipboardModule()
        let stats = SystemStatsModule()
        let ports = PortSniperModule()
        host = ModuleHost(modules: [clipboard, ports, stats], topAccessory: clipboard.makeStashView())
        host.startAll()

        controller = NotchController(host: host)
        setUpStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        host?.stopAll()
    }

    func showSettings() {
        NotchController.shared.collapse()
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: .shared)))
            window.title = "NotChi Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "NotChi")

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Notch", action: #selector(openNotch), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit NotChi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func openNotch() { NotchController.shared.expand(sticky: true) }
    @objc private func openSettings() { showSettings() }
}
