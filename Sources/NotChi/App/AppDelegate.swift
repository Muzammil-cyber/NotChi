// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var shared: AppDelegate?

    private var host: ModuleHost!
    private var transfer: TransferCoordinator?
    private var nowPlaying: NowPlayingModule!
    private var controller: NotchController!
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self

        let clipboard = ClipboardModule()
        let dev = DevModule(tools: [PortSniperModule()])
        let stats = SystemStatsModule()
        nowPlaying = NowPlayingModule()
        // Pane order is also wing priority: music, then an upcoming meeting, then stats.
        let overview = OverviewModule(panes: [nowPlaying, CalendarModule()])
        transfer = TransferCoordinator(stash: clipboard.stash)
        host = ModuleHost(tabs: [overview, clipboard, dev], background: [stats],
                          topAccessory: clipboard.makeStashView(), headerAccessory: stats.makeHeaderView(),
                          transfer: transfer)
        host.startAll()

        controller = NotchController(host: host)
        updateStatusItem()
        observeAutomation()
        NSLog("NotChi launched; accessibility trusted: %@", Permissions.isAccessibilityTrusted ? "yes" : "no")
    }

    /// Lets scripts (Raycast, Shortcuts, shell) drive the notch:
    /// post `com.notchi.app.open` with an optional tab or section id as the object
    /// ("overview", "clipboard", "dev"; "nowplaying"/"calendar" open Overview, "ports" opens Dev),
    /// `com.notchi.app.close`, `com.notchi.app.settings` with an optional tab id,
    /// `com.notchi.app.send` with "iphone:<path>" / "android:<path>", or
    /// `com.notchi.app.media` with "toggle", "next" or "previous".
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
        // Object: "iphone:/path/to/file" or "android:/path/to/file".
        center.addObserver(forName: .init("com.notchi.app.send"), object: nil, queue: .main) { note in
            guard let spec = note.object as? String, let colon = spec.firstIndex(of: ":") else { return }
            let target = spec[..<colon].lowercased()
            let url = URL(fileURLWithPath: String(spec[spec.index(after: colon)...]))
            MainActor.assumeIsolated {
                guard let transfer = TransferCoordinator.shared else { return }
                if target == "android", transfer.canSendToAndroid { transfer.sendToAndroid([url]) }
                if target == "iphone", transfer.canSendToiPhone { transfer.sendToiPhone([url]) }
            }
        }
        center.addObserver(forName: .init("com.notchi.app.media"), object: nil, queue: .main) { note in
            let command = note.object as? String
            MainActor.assumeIsolated {
                guard let model = AppDelegate.shared?.nowPlaying.model else { return }
                switch command {
                case "toggle": model.togglePlayPause()
                case "next": model.next()
                case "previous": model.previous()
                default: break
                }
            }
        }
        center.addObserver(forName: .init("com.notchi.app.settings"), object: nil, queue: .main) { note in
            let tab = (note.object as? String).flatMap(SettingsTab.init(automationID:))
            MainActor.assumeIsolated { AppDelegate.shared?.showSettings(tab: tab) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        host?.stopAll()
        transfer?.stop()
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
        item.button?.image = MenuBarIcon.image()

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
