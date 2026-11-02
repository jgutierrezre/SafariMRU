//
//  SettingsWindowController.swift
//  SafariMRU
//
//  Settings window: launch-at-login toggle and Ctrl+number shortcut toggle.
//

import Cocoa
import ServiceManagement

enum Settings {
    private static let numberShortcutsKey = "enableNumberShortcuts"

    /// Whether Ctrl+1…9 / Ctrl+0 jump to tabs. Defaults to true.
    static var numberShortcutsEnabled: Bool {
        get { (UserDefaults.standard.object(forKey: numberShortcutsKey) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: numberShortcutsKey) }
    }
}

final class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Safari MRU"
        window.isReleasedWhenClosed = false
        self.init(window: window)

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 180))

        let loginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(toggleLogin(_:)))
        loginCheckbox.frame = NSRect(x: 20, y: 140, width: 280, height: 22)
        loginCheckbox.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        content.addSubview(loginCheckbox)

        let numberCheckbox = NSButton(checkboxWithTitle: "Enable Ctrl+1–9 tab shortcuts", target: self, action: #selector(toggleNumberShortcuts(_:)))
        numberCheckbox.frame = NSRect(x: 20, y: 110, width: 300, height: 22)
        numberCheckbox.state = Settings.numberShortcutsEnabled ? .on : .off
        content.addSubview(numberCheckbox)

        let note = NSTextField(labelWithString: "Ctrl+1–9 jumps to a tab (MRU order during a cycle, tab-bar order otherwise). Turn this off if it conflicts with Mission Control space switching.")
        note.frame = NSRect(x: 20, y: 40, width: 300, height: 60)
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
}
