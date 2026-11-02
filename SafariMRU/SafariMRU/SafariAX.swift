//
//  SafariAX.swift
//  SafariMRU
//
//  Accessibility (AX) access to Safari's tabs. Safari exposes its tabs as
//  AXRadioButton elements with subrole AXTabButton; we enumerate them and can
//  AXPress the target tab to switch to it.
//

import Cocoa
import ApplicationServices

final class SafariAX {
    private static let roleRadio = "AXRadioButton"
    private static let subTab = "AXTabButton"
    private static let roleWebArea = "AXWebArea"

    private static func safariApp() -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first else {
            return nil
        }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    private static func focusedWindow() -> AXUIElement? {
        guard let app = safariApp() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as! AXUIElement
    }

    private static func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func strAttr(_ el: AXUIElement, _ name: String) -> String {
        return (attr(el, name) as? String) ?? ""
    }

    /// Recursively collect Safari tab-bar buttons, skipping web content so
    /// page-level radio buttons are not picked up.
    private static func collectTabs(from el: AXUIElement, into tabs: inout [AXUIElement]) {
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

    private static func findTabs() -> [AXUIElement] {
        guard let win = focusedWindow() else { return [] }
        var tabs: [AXUIElement] = []
        collectTabs(from: win, into: &tabs)
        return tabs
    }

    private static func tabValue(_ tab: AXUIElement) -> Int {
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

    /// Switch Safari's focused window to the tab matching the given title,
    /// falling back to the 0-based index if no title matches.
    static func switchToTab(title: String, fallbackIndex: Int) {
        let tabs = findTabs()
        guard !tabs.isEmpty else { return }

        if !title.isEmpty {
            for t in tabs where strAttr(t, kAXTitleAttribute) == title {
                AXUIElementPerformAction(t, kAXPressAction as CFString)
                return
            }
        }

        if fallbackIndex >= 0 && fallbackIndex < tabs.count {
            AXUIElementPerformAction(tabs[fallbackIndex], kAXPressAction as CFString)
        }
    }

    /// Returns a title -> favicon image data map by walking the tab bar once.
    static func faviconDataByTitle() -> [String: Data] {
        var result: [String: Data] = [:]
        let tabs = findTabs()
        var noImage = 0
        for t in tabs {
            let title = strAttr(t, kAXTitleAttribute)
            guard !title.isEmpty, result[title] == nil else { continue }
            if let data = faviconData(for: t) {
                result[title] = data
            } else {
                noImage += 1
            }
        }
        DebugLog.shared.log("favicons: \(result.count)/\(tabs.count) extracted (\(noImage) without image)")
        return result
    }

    private static func faviconData(for tab: AXUIElement) -> Data? {
        guard let children = attr(tab, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for c in children where strAttr(c, kAXRoleAttribute) == "AXImage" {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(c, "AXImageData" as CFString, &value) == .success,
                  let value = value else { continue }

            let typeID = CFGetTypeID(value)

            if let nsData = value as? NSData {
                return nsData as Data
            }
            if let nsImage = value as? NSImage, let tiff = nsImage.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff) {
                return rep.representation(using: .png, properties: [:])
            }
            if typeID == CGImage.typeID {
                let image = value as! CGImage
                return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            }

            // AXImageData is an array of image representations.
            if let arr = value as? [Any] {
                for item in arr {
                    if let d = item as? NSData {
                        return d as Data
                    }
                    if let img = item as? NSImage, let tiff = img.tiffRepresentation,
                       let rep = NSBitmapImageRep(data: tiff) {
                        return rep.representation(using: .png, properties: [:])
                    }
                }
            }
        }
        return nil
    }
}
