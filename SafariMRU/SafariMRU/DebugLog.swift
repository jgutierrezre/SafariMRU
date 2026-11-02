//
//  DebugLog.swift
//  SafariMRU
//
//  Minimal file logger for diagnosing the extension -> app pipeline.
//

import Foundation

final class DebugLog {
    static let shared = DebugLog()
    private let url: URL
    private let lock = NSLock()

    init() {
        url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("mru-debug.log")
        try? FileManager.default.removeItem(at: url)
    }

    func log(_ msg: String) {
        lock.lock()
        defer { lock.unlock() }
        let line = "\(Date()) \(msg)\n"
        if let data = line.data(using: .utf8) {
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(data)
                try? h.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
