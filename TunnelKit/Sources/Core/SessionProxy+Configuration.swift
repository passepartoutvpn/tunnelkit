//
//  SessionProxy+Configuration.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 8/23/18.
//  Copyright (c) 2018 Davide De Rosa. All rights reserved.
//
//  https://github.com/keeshux
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
//

import Foundation

extension SessionProxy {

    /// The available encryption algorithms.
    public enum Cipher: String, Codable, CustomStringConvertible {
        
        // WARNING: must match OpenSSL algorithm names
        
        /// AES encryption with 128-bit key size and CBC.
        case aes128cbc = "AES-128-CBC"
        
        /// AES encryption with 192-bit key size and CBC.
        case aes192cbc = "AES-192-CBC"
        
        /// AES encryption with 256-bit key size and CBC.
        case aes256cbc = "AES-256-CBC"
        
        /// AES encryption with 128-bit key size and GCM.
        case aes128gcm = "AES-128-GCM"
        
        /// AES encryption with 192-bit key size and GCM.
        case aes192gcm = "AES-192-GCM"
        
        /// AES encryption with 256-bit key size and GCM.
        case aes256gcm = "AES-256-GCM"
        
        /// Digest should be ignored when this is `true`.
        public var embedsDigest: Bool {
            return rawValue.hasSuffix("-GCM")
        }
        
        /// Returns a generic name for this cipher.
        public var genericName: String {
            return rawValue.hasSuffix("-GCM") ? "AES-GCM" : "AES-CBC"
        }
        
        /// :nodoc:
        public var description: String {
            return rawValue
        }
    }
    
    /// The available message digest algorithms.
    public enum Digest: String, Codable, CustomStringConvertible {
        
        // WARNING: must match OpenSSL algorithm names
        
        /// SHA1 message digest.
        case sha1 = "SHA1"
        
        /// SHA224 message digest.
        case sha224 = "SHA224"

        /// SHA256 message digest.
        case sha256 = "SHA256"

        /// SHA256 message digest.
        case sha384 = "SHA384"

        /// SHA256 message digest.
        case sha512 = "SHA512"
        
        /// Returns a generic name for this digest.
        public var genericName: String {
            return "HMAC"
        }
        
        /// :nodoc:
        public var description: String {
            return "\(genericName)-\(rawValue)"
        }
    }
    
    /// The way to create a `SessionProxy.Configuration` object for a `SessionProxy`.
    public struct ConfigurationBuilder {

        /// An username.
        public let username: String
        
        /// A password.
        public let password: String
        
        /// The cipher algorithm for data encryption.
        public var cipher: Cipher
        
        /// The digest algorithm for HMAC.
        public var digest: Digest
        
        /// The path to the optional CA for TLS negotiation (PEM format).
        public var caPath: String?
        
        /// The path to the optional client certificate for TLS negotiation (PEM format).
        public var clientCertificatePath: String?
        
        /// The path to the private key for the certificate at `clientCertificatePath` (PEM format).
        public var clientKeyPath: String?
        
        /// Sets compression framing, disabled by default.
        public var compressionFraming: CompressionFraming

        /// Sends periodical keep-alive packets if set.
        public var keepAliveInterval: TimeInterval?
        
        /// The number of seconds after which a renegotiation should be initiated. If `nil`, the client will never initiate a renegotiation.
        public var renegotiatesAfter: TimeInterval?
        
        /// :nodoc:
        public init(username: String, password: String) {
            self.username = username
            self.password = password
            cipher = .aes128cbc
            digest = .sha1
            caPath = nil
            clientCertificatePath = nil
            clientKeyPath = nil
            compressionFraming = .disabled
            keepAliveInterval = nil
            renegotiatesAfter = nil
        }

        /**
         Builds a `SessionProxy.Configuration` object.
         
         - Returns: A `SessionProxy.Configuration` object with this builder.
         */
        public func build() -> Configuration {
            return Configuration(
                username: username,
                password: password,
                cipher: cipher,
                digest: digest,
                caPath: caPath,
                clientCertificatePath: clientCertificatePath,
                clientKeyPath: clientKeyPath,
                compressionFraming: compressionFraming,
                keepAliveInterval: keepAliveInterval,
                renegotiatesAfter: renegotiatesAfter
            )
        }
    }
    
    /// The immutable configuration for `SessionProxy`.
    public struct Configuration: Codable {

        /// - Seealso: `SessionProxy.ConfigurationBuilder.username`
        public let username: String
        
        /// - Seealso: `SessionProxy.ConfigurationBuilder.password`
        public let password: String
        
        /// - Seealso: `SessionProxy.ConfigurationBuilder.cipher`
        public let cipher: Cipher
        
        /// - Seealso: `SessionProxy.ConfigurationBuilder.digest`
        public let digest: Digest
        
        /// - Seealso: `SessionProxy.ConfigurationBuilder.caPath`
        public let caPath: String?
        
        /// - Seealso: `SessionProxy.ConfigurationBuilder.clientCertificatePath`
        public let clientCertificatePath: String?
        
        /// - Seealso: `SessionProxy.ConfigurationBuilder.clientKeyPath`
        public let clientKeyPath: String?
        
        /// - Seealso: `SessionProxy.ConfigurationBuilder.compressionFraming`
        public let compressionFraming: CompressionFraming

        /// - Seealso: `SessionProxy.ConfigurationBuilder.keepAliveInterval`
        public let keepAliveInterval: TimeInterval?

        /// - Seealso: `SessionProxy.ConfigurationBuilder.renegotiatesAfter`
        public let renegotiatesAfter: TimeInterval?
    }
}
