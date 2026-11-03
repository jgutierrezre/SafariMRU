//
//  MRUTracker.swift
//  SafariMRU
//
//  Native, event-driven MRU tracking. An AXObserver on Safari notify us of
//  focused-UI changes (which fire after a tab switch), and we read the active
//  tab to update the MRU order — no polling, no extension.
//

import Cocoa
import ApplicationServices

struct TabPreview {
    let title: String
    let url: String
    let index: Int
}

final class MRUTracker {
    static let shared = MRUTracker()

    private let lock = NSLock()
    private var mru: [String] = []            // titles, most recent first
    private var currentTitles: [String] = []  // AX (tab-bar) order
    private var lastActive: String?
    private var observer: AXObserver?
    private var observedPID: pid_t = 0

    func start() {
        ensureObserver()
        sync()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier == "com.apple.Safari" {
                self?.ensureObserver()
                self?.sync()
            }
        }
    }

    /// Current MRU-ordered tabs (title + current tab-bar index).
    func tabs() -> [TabPreview] {
        sync()
        lock.lock()
        defer { lock.unlock() }
        var result: [TabPreview] = []
        for title in mru {
            if let idx = currentTitles.firstIndex(of: title) {
                result.append(TabPreview(title: title, url: "", index: idx))
            }
        }
        return result
    }

    func title(atBarIndex index: Int) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard index >= 0 && index < currentTitles.count else { return nil }
        return currentTitles[index]
    }

    var tabCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return currentTitles.count
    }

    var currentActiveTitle: String? {
        lock.lock()
        defer { lock.unlock() }
        return lastActive
    }

    /// Move a title to the front of the MRU stack.
    func promote(_ title: String) {
        lock.lock()
        mru.removeAll { $0 == title }
        mru.insert(title, at: 0)
        lastActive = title
        lock.unlock()
    }

    /// Re-read Safari's tabs and update the MRU order.
    func sync() {
        guard let (active, titles) = SafariAX.getTabInfo(), active >= 0, active < titles.count else { return }

        lock.lock()
        currentTitles = titles
        mru = mru.filter { titles.contains($0) }
        for t in titles where !mru.contains(t) { mru.append(t) }

        let a = titles[active]
        if a != lastActive {
            mru.removeAll { $0 == a }
            mru.insert(a, at: 0)
            lastActive = a
        }
        lock.unlock()
    }

    private func ensureObserver() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first else {
            return
        }
        if observer != nil && observedPID == app.processIdentifier { return }

        var obs: AXObserver?
        guard AXObserverCreate(app.processIdentifier, mruObserverCallback, &obs) == .success,
              let observer = obs else {
            return
        }
        AXObserverAddNotification(
            observer,
            AXUIElementCreateApplication(app.processIdentifier),
            kAXFocusedUIElementChangedNotification as CFString,
            nil
        )
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        self.observer = observer
        self.observedPID = app.processIdentifier
    }
}

private func mruObserverCallback(observer: AXObserver, element: AXUIElement, notification: CFString, refcon: UnsafeMutableRawPointer?) {
    MRUTracker.shared.sync()
}
