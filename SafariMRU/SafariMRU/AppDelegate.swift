//
//  AppDelegate.swift
//  SafariMRU
//
//  Menu-bar agent that intercepts Ctrl+Tab / Ctrl+Shift+Tab and performs
//  most-recently-used (MRU) tab switching in Safari via the Accessibility API.
//

import Cocoa
import ApplicationServices
import ServiceManagement

private let kVK_Tab: CGKeyCode = 48

// MARK: - Accessibility access to Safari tabs

final class SafariAX {
    private static let roleRadio = "AXRadioButton"
    private static let subTab = "AXTabButton"
    private static let roleWebArea = "AXWebArea"

    static func safariApp() -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first else {
            return nil
        }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    static func focusedWindow() -> AXUIElement? {
        guard let app = safariApp() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as! AXUIElement
    }

    static func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func strAttr(_ el: AXUIElement, _ name: String) -> String {
        return (attr(el, name) as? String) ?? ""
    }

    /// Recursively collect Safari tab-bar buttons (AXRadioButton/AXTabButton),
    /// skipping web content so page radio buttons are not picked up.
    static func collectTabs(from el: AXUIElement, into tabs: inout [AXUIElement]) {
        let role = strAttr(el, kAXRoleAttribute)
        if role == roleWebArea { return }
        if role == roleRadio && strAttr(el, kAXSubroleAttribute) == subTab {
            tabs.append(el)
            return
        }
        if let children = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
            for c in children { collectTabs(from: c, into: &tabs) }
        }
    }

    static func findTabs() -> [AXUIElement] {
        guard let win = focusedWindow() else { return [] }
        var tabs: [AXUIElement] = []
        collectTabs(from: win, into: &tabs)
        return tabs
    }

    static func tabValue(_ tab: AXUIElement) -> Int {
        if let v = attr(tab, kAXValueAttribute) as? NSNumber { return v.intValue }
        return -1
    }

    /// Returns (activeIndex, titles) for the focused Safari window, or nil.
    static func getTabInfo() -> (activeIndex: Int, titles: [String])? {
        let tabs = findTabs()
        guard !tabs.isEmpty else { return nil }

        var titles: [String] = []
        var active = -1
        for (i, t) in tabs.enumerated() {
            titles.append(strAttr(t, kAXTitleAttribute))
            if tabValue(t) == 1 { active = i }
        }
        if active == -1, let win = focusedWindow() {
            let wt = strAttr(win, kAXTitleAttribute)
            if let idx = titles.firstIndex(of: wt) { active = idx }
        }
        if active == -1 { active = 0 }
        return (active, titles)
    }

    static func switchToTab(index: Int) {
        let tabs = findTabs()
        guard index >= 0 && index < tabs.count else { return }
        AXUIElementPerformAction(tabs[index], kAXPressAction as CFString)
    }
}

// MARK: - MRU switcher

final class MRUSwitcher {
    static let shared = MRUSwitcher()
    private let queue = DispatchQueue(label: "mru.switcher")

    /// Tab titles in MRU order; index 0 = most recently used.
    private var mru: [String] = []
    private var activeTitle: String?
    private var isCycling = false
    private var cyclePos = 0
    /// Title of the tab we just switched to (so polling ignores our own switch).
    private var expectedTitle: String?
    private var pollTimer: DispatchSourceTimer?

    func start() {
        queue.async { self.initialSync() }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.4)
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        pollTimer = timer
    }

    private func initialSync() {
        guard let (active, titles) = SafariAX.getTabInfo() else { return }
        let a = titles[active]
        var seed = [a]
        for (i, t) in titles.enumerated() where i != active {
            if !seed.contains(t) { seed.append(t) }
        }
        mru = seed
        activeTitle = a
    }

    private func poll() {
        guard let (active, titles) = SafariAX.getTabInfo() else { return }
        let a = titles[active]

        var newMru = mru.filter { titles.contains($0) }
        for t in titles where !newMru.contains(t) { newMru.append(t) }
        mru = newMru

        if activeTitle != a {
            if let exp = expectedTitle, exp == a {
                expectedTitle = nil
            } else if isCycling {
                isCycling = false
                cyclePos = 0
                promote(a)
            } else {
                promote(a)
            }
            activeTitle = a
        }
    }

    private func promote(_ title: String) {
        mru.removeAll { $0 == title }
        mru.insert(title, at: 0)
    }

    func cycleForward() { queue.async { self.doCycle(1) } }
    func cycleBackward() { queue.async { self.doCycle(-1) } }
    func commit() { queue.async { self.doCommit() } }

    private func doCycle(_ direction: Int) {
        guard let (active, titles) = SafariAX.getTabInfo() else { return }
        let a = titles[active]
        activeTitle = a

        if !isCycling {
            // A cycle must begin with a forward press (Ctrl+Tab). Backward first does nothing.
            if direction < 0 { return }
            if mru.isEmpty {
                initialSync()
                if mru.isEmpty { return }
            }
            // Sync the active tab to the front (catches a click the poll hasn't seen yet).
            if mru.first != a { promote(a) }
            isCycling = true
            cyclePos = 0
        }

        guard mru.count > 1 else { return }

        if direction > 0 {
            cyclePos += 1
            if cyclePos >= mru.count { cyclePos = 1 }
        } else {
            if cyclePos > 0 { cyclePos -= 1 }
        }

        let target = mru[cyclePos]
        guard let idx = titles.firstIndex(of: target) else {
            mru.removeAll { $0 == target }
            isCycling = false
            cyclePos = 0
            return
        }
        expectedTitle = target
        SafariAX.switchToTab(index: idx)
    }

    private func doCommit() {
        guard isCycling else { return }
        let target = mru[cyclePos]
        promote(target)
        isCycling = false
        cyclePos = 0
    }
}

// MARK: - Event tap (intercepts Ctrl+Tab)

final class ShortcutInterceptor {
    static let shared = ShortcutInterceptor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isCycling = false

    private let safariBundleID = "com.apple.Safari"

    func start() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    fileprivate func handleCGEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == safariBundleID else {
            if isCycling {
                isCycling = false
                MRUSwitcher.shared.commit()
            }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags

        if type == .flagsChanged {
            if isCycling && !flags.contains(.maskControl) {
                isCycling = false
                MRUSwitcher.shared.commit()
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let isCtrl = flags.contains(.maskControl)
            let isCmdOrOpt = flags.contains(.maskCommand) || flags.contains(.maskAlternate)

            if keyCode == kVK_Tab && isCtrl && !isCmdOrOpt {
                isCycling = true
                if flags.contains(.maskShift) {
                    MRUSwitcher.shared.cycleBackward()
                } else {
                    MRUSwitcher.shared.cycleForward()
                }
                return nil // swallow so Safari does not switch sequentially
            }
        }

        return Unmanaged.passUnretained(event)
    }
}

private func tapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let interceptor = Unmanaged<ShortcutInterceptor>.fromOpaque(refcon).takeUnretainedValue()
    return interceptor.handleCGEvent(proxy: proxy, type: type, event: event)
}

// MARK: - Settings window

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

// MARK: - App delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "SafariMRU"
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
        MRUSwitcher.shared.start()
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
