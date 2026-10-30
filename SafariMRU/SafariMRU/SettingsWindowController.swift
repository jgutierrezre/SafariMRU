//
//  SettingsWindowController.swift
//  SafariMRU
//
//  A simple settings window with a "Launch at login" toggle backed by
//  SMAppService.
//

import Cocoa
import ServiceManagement

final class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Safari MRU"
        window.isReleasedWhenClosed = false
        self.init(window: window)

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))

        let checkbox = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(toggleLogin(_:)))
        checkbox.frame = NSRect(x: 20, y: 76, width: 200, height: 22)
        checkbox.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        content.addSubview(checkbox)

        let note = NSTextField(labelWithString: "Runs Safari MRU automatically when you log in, so Ctrl+Tab switching is always available.")
        note.frame = NSRect(x: 20, y: 36, width: 280, height: 36)
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
}
