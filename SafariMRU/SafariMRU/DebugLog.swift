//
//  DebugLog.swift
//  SafariMRU
//
//  Minimal file logger for diagnosing AX / favicon issues. Debug builds only:
//  release builds compile the body away so nothing is written to the user's
//  home directory.
//

import Foundation

final class DebugLog {
    static let shared = DebugLog()

    private let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("mru-debug.log")
    private let lock = NSLock()

    init() {
        #if DEBUG
        try? FileManager.default.removeItem(at: url)
        #endif
    }

    func log(_ msg: String) {
        #if DEBUG
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
        #endif
    }
}
