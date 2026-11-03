//
//  SettingsWindowController.swift
//  SafariMRU
//
//  Settings window: launch-at-login, Ctrl+number shortcuts, tab thumbnails.
//

import Cocoa
import CoreGraphics
import ServiceManagement

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

final class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 210),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Safari MRU"
        window.isReleasedWhenClosed = false
        self.init(window: window)

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 210))

        let loginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(toggleLogin(_:)))
        loginCheckbox.frame = NSRect(x: 20, y: 172, width: 300, height: 22)
        loginCheckbox.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        content.addSubview(loginCheckbox)

        let numberCheckbox = NSButton(checkboxWithTitle: "Enable Ctrl+1–9 tab shortcuts", target: self, action: #selector(toggleNumberShortcuts(_:)))
        numberCheckbox.frame = NSRect(x: 20, y: 144, width: 320, height: 22)
        numberCheckbox.state = Settings.numberShortcutsEnabled ? .on : .off
        content.addSubview(numberCheckbox)

        let thumbsCheckbox = NSButton(checkboxWithTitle: "Show tab thumbnails (requires Screen Recording)", target: self, action: #selector(toggleThumbnails(_:)))
        thumbsCheckbox.frame = NSRect(x: 20, y: 116, width: 320, height: 22)
        thumbsCheckbox.state = Settings.thumbnailsEnabled ? .on : .off
        content.addSubview(thumbsCheckbox)

        let note = NSTextField(labelWithString: "Ctrl+1–9 jumps to a tab (MRU order during a cycle, tab-bar order otherwise). Thumbnails capture the visible tab only, so they build up as you visit tabs.")
        note.frame = NSRect(x: 20, y: 40, width: 320, height: 66)
        note.lineBreakMode = .byWordWrapping
        note.textColor = .secondaryLabelColor
        note.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        content.addSubview(note)

        window.contentView = content
        window.center()
    }

    @objc private func toggleLogin(_ sender: NSButton) {
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't update login item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            sender.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        }
    }

    @objc private func toggleNumberShortcuts(_ sender: NSButton) {
        Settings.numberShortcutsEnabled = (sender.state == .on)
    }

    @objc private func toggleThumbnails(_ sender: NSButton) {
        let on = (sender.state == .on)
        Settings.thumbnailsEnabled = on
        if on && !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        if !on {
            ThumbnailStore.shared.clear()
        }
    }
}
