//
//  WgStats.swift
//
//
//  Created by Yevgeny Yezub on 16/11/23.
//

import Foundation

public struct WgStats {
    public let bytesReceived: UInt64
    public let bytesSent: UInt64

    public init(bytesReceived: UInt64 = 0, bytesSent: UInt64 = 0) {
        self.bytesReceived = bytesReceived
        self.bytesSent = bytesSent
    }
}

@inline(__always) private func parseValue(_ prefixKey: String, in line: String) -> UInt64? {
    guard line.hasPrefix(prefixKey) else { return nil }

    let value = line.dropFirst(prefixKey.count)

    return UInt64(value)
}
