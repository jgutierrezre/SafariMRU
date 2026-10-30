//
//  PreviewState.swift
//  SafariMRU
//
//  Shared tab state, populated by the Safari extension over localhost. Holds
//  the MRU-ordered list of tabs with metadata and thumbnails for the preview.
//

import Cocoa

struct TabPreview {
    let title: String
    let url: String
    let favIconUrl: String
    let index: Int
    let thumbnail: String // data URL, or empty
}

final class PreviewState {
    static let shared = PreviewState()

    private let lock = NSLock()
    private var _tabs: [TabPreview] = []

    var tabs: [TabPreview] {
        lock.lock()
        defer { lock.unlock() }
        return _tabs
    }

    func applyJSON(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        let rawTabs = obj["tabs"] as? [[String: Any]] ?? []
        var parsed: [TabPreview] = []
        for t in rawTabs {
            parsed.append(TabPreview(
                title: t["title"] as? String ?? "",
                url: t["url"] as? String ?? "",
                favIconUrl: t["favIconUrl"] as? String ?? "",
                index: t["index"] as? Int ?? 0,
                thumbnail: t["thumbnail"] as? String ?? ""
            ))
        }
        lock.lock()
        _tabs = parsed
        lock.unlock()
    }
}
