//
//  SafariWebExtensionHandler.swift
//  SafariMRU Extension
//
//  Native messaging handler. We use a localhost HTTP channel instead of native
//  messaging, so this is a minimal stub required as the extension's principal
//  class.
//

import SafariServices
import os.log

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let response = NSExtensionItem()
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
