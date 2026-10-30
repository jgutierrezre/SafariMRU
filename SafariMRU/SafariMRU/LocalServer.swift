//
//  LocalServer.swift
//  SafariMRU
//
//  A tiny localhost HTTP server that receives tab-state POSTs from the Safari
//  extension (see extension/background.js) and applies them to PreviewState.
//

import Cocoa
import Network

final class LocalServer {
    static let shared = LocalServer()
    private let port: UInt16 = 49153
    private var listener: NWListener?

    func start() {
        do {
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
            listener.newConnectionHandler = { conn in
                ConnectionHandler().handle(conn)
            }
            listener.start(queue: .global(qos: .utility))
            self.listener = listener
        } catch {
            NSLog("LocalServer failed to start: \(error)")
        }
    }

    static func extractJSONBody(from data: Data) -> Data? {
        let headerEnd = data.range(of: Data("\r\n\r\n".utf8))
        guard let headerEnd = headerEnd else { return nil }

        let headerData = data[..<headerEnd.lowerBound]
        let headerStr = String(data: headerData, encoding: .utf8) ?? ""
        var contentLength = 0
        for line in headerStr.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }

        let bodyStart = headerEnd.upperBound
        guard contentLength > 0, data.count >= bodyStart + contentLength else { return nil }
        return data.subdata(in: bodyStart..<(bodyStart + contentLength))
    }
}

private final class ConnectionHandler {
    private var data = Data()

    func handle(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .utility))
        receive(conn)
    }

    private func receive(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] chunk, _, isComplete, error in
            guard let self = self else { return }

            if let chunk = chunk, !chunk.isEmpty {
                self.data.append(chunk)
                if let body = LocalServer.extractJSONBody(from: self.data) {
                    PreviewState.shared.applyJSON(body)
                    let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                    conn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                        conn.cancel()
                    })
                    return
                }
            }

            if isComplete || error != nil {
                conn.cancel()
            } else {
                self.receive(conn)
            }
        }
    }
}
