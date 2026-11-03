//
//  SettingsWindowController.swift
//  SafariMRU
//
//  Settings window: launch-at-login, Ctrl+number shortcuts, tab thumbnails.
//  Built with SwiftUI's grouped Form for a native macOS settings look.
//

import Cocoa
import CoreGraphics
import ServiceManagement
import SwiftUI

enum Settings {
    private static let numberShortcutsKey = "enableNumberShortcuts"
    private static let thumbnailsKey = "enableThumbnails"

    /// Whether Ctrl+1…9 / Ctrl+0 jump to tabs. Defaults to true.
    static var numberShortcutsEnabled: Bool {
        get { (UserDefaults.standard.object(forKey: numberShortcutsKey) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: numberShortcutsKey) }
    }

    /// Whether tab thumbnails are captured. Defaults to false (needs Screen Recording).
    static var thumbnailsEnabled: Bool {
        get { (UserDefaults.standard.object(forKey: thumbnailsKey) as? Bool) ?? false }
        set { UserDefaults.standard.set(newValue, forKey: thumbnailsKey) }
    }
}

@MainActor
struct SettingsView: View {
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var numberShortcuts = Settings.numberShortcutsEnabled
    @State private var thumbnails = Settings.thumbnailsEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLogin(newValue)
                    }
            }

            Section {
                Toggle("Enable Ctrl+1–9 tab shortcuts", isOn: $numberShortcuts)
                    .onChange(of: numberShortcuts) { _, newValue in
                        Settings.numberShortcutsEnabled = newValue
                    }
            } footer: {
                Text("Ctrl+1–9 jumps to a tab — MRU order during a cycle, tab-bar order otherwise. Turn this off if it conflicts with Mission Control space switching.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show tab thumbnails", isOn: $thumbnails)
                    .onChange(of: thumbnails) { _, newValue in
                        Settings.thumbnailsEnabled = newValue
                        if newValue {
                            if !CGPreflightScreenCaptureAccess() {
                                CGRequestScreenCaptureAccess()
                            }
                        } else {
                            ThumbnailStore.shared.clear()
                        }
                    }
            } footer: {
                Text("Captures the visible tab only (requires Screen Recording), so thumbnails build up as you visit tabs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 300)
    }

    private func setLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't update login item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }
}

final class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Safari MRU"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView())
        self.init(window: window)
        window.center()
    }
}
