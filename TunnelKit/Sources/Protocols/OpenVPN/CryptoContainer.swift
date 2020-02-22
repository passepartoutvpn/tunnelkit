//
//  CryptoContainer.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 8/22/18.
//  Copyright (c) 2020 Davide De Rosa. All rights reserved.
//
//  https://github.com/passepartoutvpn
//
//  This file is part of TunnelKit.
//
//  TunnelKit is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  TunnelKit is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with TunnelKit.  If not, see <http://www.gnu.org/licenses/>.
//
//  This file incorporates work covered by the following copyright and
//  permission notice:
//
//      Copyright (c) 2018-Present Private Internet Access
//
//      Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//      The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//      THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

import Foundation
import __TunnelKitOpenVPN

extension OpenVPN {

    /// Represents a cryptographic container in PEM format.
    public struct CryptoContainer: Codable, Equatable {
        private static let begin = "-----BEGIN "

        private static let end = "-----END "
        
        /// The content in PEM format (ASCII).
        public let pem: String
        
        var isEncrypted: Bool {
            return pem.contains("ENCRYPTED")
        }
        
        /// :nodoc:
        public init(pem: String) {
            guard let beginRange = pem.range(of: CryptoContainer.begin) else {
                self.pem = ""
                return
            }
            self.pem = String(pem[beginRange.lowerBound...])
        }
        
        func write(to url: URL) throws {
            try pem.write(to: url, atomically: true, encoding: .ascii)
        }

        func decrypted(with passphrase: String) throws -> CryptoContainer {
            let decryptedPEM = try TLSBox.decryptedPrivateKey(fromPEM: pem, passphrase: passphrase)
            return CryptoContainer(pem: decryptedPEM)
        }

        // MARK: Equatable
        
        /// :nodoc:
        public static func ==(lhs: CryptoContainer, rhs: CryptoContainer) -> Bool {
            return lhs.pem == rhs.pem
        }

        // MARK: Codable
        
        /// :nodoc:
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let pem = try container.decode(String.self)
            self.init(pem: pem)
        }
        
        /// :nodoc:
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(pem)
        }
    }
    
    public struct Host: Codable, Equatable {
        
        public let hostName: String?
        public let port: UInt16?
        public let socketType: SocketType?
        
        public init(_ hostName: String?, _ port: UInt16?, _ socketType: SocketType?) {
            self.hostName = hostName
            self.port = port
            self.socketType = socketType
        }
        
        // MARK: Equatable

        public static func ==(lhs: Host, rhs: Host) -> Bool {
            return (lhs.hostName == rhs.hostName) && (lhs.port == rhs.port) && (lhs.socketType == rhs.socketType)
        }
        
        enum CodingKeys: String, CodingKey {
           case hostName
           case port
           case socketType
        }

        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let hostName = try container.decode(String.self, forKey: .hostName)
            let port = try container.decode(UInt16.self, forKey: .port)
            let socketType = try container.decode(String.self, forKey: .socketType)
            self.init(hostName,port,SocketType(rawValue: socketType))
        }
        
        /// :nodoc:
        public func encode(to encoder: Encoder) throws {
            var container = try encoder.container(keyedBy: CodingKeys.self)
            try container.encode(hostName, forKey: .hostName)
            try container.encode(port, forKey: .port)
            try container.encode(socketType?.rawValue, forKey: .socketType)
        }
    }
}
