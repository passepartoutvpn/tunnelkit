import TunnelKitWireGuardCore
import TunnelKitWireGuardManager

// SPDX-License-Identifier: MIT
// Copyright © 2018-2021 WireGuard LLC. All Rights Reserved.

import NetworkExtension

class ErrorNotifier {
    private let appGroupId: String
    
    private var sharedFolderURL: URL? {
        guard let sharedFolderURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            wg_log(.error, message: "Cannot obtain shared folder URL")
            return nil
        }
        return sharedFolderURL
    }

    init(appGroupId: String) {
        self.appGroupId = appGroupId
        removeLastErrorFile()
    }

    func notify(_ error: WireGuardProviderError) {
        guard let lastErrorFilePath = networkExtensionLastErrorFileURL?.path else {
            return
        }
        let errorMessageData = "\(error)".data(using: .utf8)
        FileManager.default.createFile(atPath: lastErrorFilePath, contents: errorMessageData, attributes: nil)
    }

    func removeLastErrorFile() {
        if let lastErrorFileURL = networkExtensionLastErrorFileURL {
            try? FileManager.default.removeItem(at: lastErrorFileURL)
        }
    }

    private var networkExtensionLastErrorFileURL: URL? {
        return sharedFolderURL?.appendingPathComponent("last-error.txt")
    }
}
