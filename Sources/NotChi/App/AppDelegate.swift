import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var shared: AppDelegate?

    private var host: ModuleHost!
    private var controller: NotchController!
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self

        let clipboard = ClipboardModule()
        let stats = SystemStatsModule()
        let ports = PortSniperModule()
        host = ModuleHost(modules: [clipboard, ports, stats], topAccessory: clipboard.makeStashView())
        host.startAll()

        controller = NotchController(host: host)
        updateStatusItem()
        observeAutomation()
        NSLog("NotChi launched; accessibility trusted: %@", Permissions.isAccessibilityTrusted ? "yes" : "no")
    }

    /// Lets scripts (Raycast, Shortcuts, shell) drive the notch:
    /// post `com.notchi.app.open` with an optional module id ("clipboard", "ports", "stats")
    /// as the object, `com.notchi.app.close`, or `com.notchi.app.settings` with an optional tab id.
    private func observeAutomation() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("com.notchi.app.open"), object: nil, queue: .main) { note in
            let moduleID = note.object as? String
            MainActor.assumeIsolated {
                if let moduleID { NotchController.shared.select(moduleID: moduleID) }
                NotchController.shared.expand(sticky: true)
            }
        }
        center.addObserver(forName: .init("com.notchi.app.close"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NotchController.shared.collapse() }
        }
        center.addObserver(forName: .init("com.notchi.app.settings"), object: nil, queue: .main) { note in
            let tab = (note.object as? String).flatMap(SettingsTab.init(rawValue:))
            MainActor.assumeIsolated { AppDelegate.shared?.showSettings(tab: tab) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        host?.stopAll()
    }

    func showSettings(tab: SettingsTab? = nil) {
        NotchController.shared.collapse()
        SettingsWindowController.show(tab: tab)
    }

    /// Adds or removes the optional menu bar icon to match Settings.
    private func updateStatusItem() {
        withObservationTracking {
            if Settings.shared.showMenuBarIcon {
                if statusItem == nil { statusItem = makeStatusItem() }
            } else if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateStatusItem() }
        }
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "NotChi")
        image?.isTemplate = true
        item.button?.image = image

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Notch", action: #selector(openNotch), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit NotChi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        return item
    }

    @objc private func openNotch() { NotchController.shared.expand(sticky: true) }
    @objc private func openSettings() { showSettings() }
}
