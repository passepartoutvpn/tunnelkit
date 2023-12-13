//
//  WireGuardDataCount.swift
//  Passepartout
//
//  Created by Yevgeny Yezub on 11/17/23.
//  Copyright (c) 2023 Yevgeny Yezub. All rights reserved.
//
//  https://github.com/passepartoutvpn
//
//  This file is part of Passepartout.
//
//  Passepartout is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Passepartout is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with Passepartout.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
/// A pair of received/sent bytes count.
public struct WireGuardDataCount: Equatable {

    /// Received bytes count.
    public let bytesReceived: UInt

    /// Sent bytes count.
    public let bytesSent: UInt

    // TODO: remove
    public let unparsedString: String

    public init(_ received: UInt, _ sent: UInt, unparsedString: String) {
        self.bytesReceived = received
        self.bytesSent = sent
        self.unparsedString = unparsedString
    }
}

extension WireGuardDataCount {
    public init?(from string: String) {
        var bytesReceived: UInt?
        var bytesSent: UInt?

        string.enumerateLines { line, stop in
            if bytesReceived == nil, let value = line.getPrefix("rx_bytes=") {
                bytesReceived = value
            } else if bytesSent == nil, let value = line.getPrefix("tx_bytes=") {
                bytesSent = value
            }

            if bytesReceived != nil, bytesSent != nil {
                stop = true
            }
        }

        guard let bytesReceived, let bytesSent else {
            return nil
        }

        self.init(bytesReceived, bytesSent, unparsedString: string)
    }
}

private extension String {
    func getPrefix(_ prefixKey: String) -> UInt? {
        guard self.hasPrefix(prefixKey) else {
            return nil
        }

        let value = self.dropFirst(prefixKey.count)

        return UInt(value)
    }
}
