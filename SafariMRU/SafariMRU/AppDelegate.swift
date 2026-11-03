//
//  AppDelegate.swift
//  SafariMRU
//
//  Menu-bar agent entry point. Creates the status item, starts the event tap
//  and MRU switcher, and hosts the settings window.
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: SettingsWindowController?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "Safari MRU")
            button.toolTip = "Safari MRU"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit Safari MRU", action: #selector(quit), keyEquivalent: "q")
        item.menu = menu

        ShortcutInterceptor.shared.start()
        _ = PreviewWindowController.shared // create the panel on the main thread
        MRUTracker.shared.start()
        ThumbnailStore.shared.start()

        // Retry until Accessibility is granted, so the app starts working
        // without a relaunch (the event tap cannot be installed before that).
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard ShortcutInterceptor.shared.isRunning else {
                ShortcutInterceptor.shared.start()
                return
            }
            timer.invalidate()
            self?.permissionTimer = nil
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController()
        }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
