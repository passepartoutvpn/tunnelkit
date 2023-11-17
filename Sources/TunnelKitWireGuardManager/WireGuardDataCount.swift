//
//  WireGuardDataCount.swift
//  
//
//  Created by Yevgeny Yezub on 17/11/23.
//

import Foundation
/// A pair of received/sent bytes count.
public struct WireGuardDataCount: Equatable {

    /// Received bytes count.
    public var bytesReceived: UInt

    /// Sent bytes count.
    public var bytesSent: UInt

    public init(_ received: UInt, _ sent: UInt) {
        self.bytesReceived = received
        self.bytesSent = sent
    }
}

extension WireGuardDataCount {
    public init?(from string: String) {
        var bytesReceived: UInt?
        var bytesSent: UInt?

        string.enumerateLines { line, stop in
            if bytesReceived == nil, let value = parseValue("rx_bytes=", in: line) {
                bytesReceived = value
            } else if bytesSent == nil, let value = parseValue("tx_bytes=", in: line) {
                bytesSent = value
            }

            if bytesReceived != nil, bytesSent != nil {
                stop = true
            }
        }

        guard let bytesReceived, let bytesSent else {
            return nil
        }

        self.init(bytesReceived, bytesSent)
    }
}

private func parseValue(_ prefixKey: String, in line: String) -> UInt? {
    guard line.hasPrefix(prefixKey) else { return nil }

    let value = line.dropFirst(prefixKey.count)

    return UInt(value)
}
