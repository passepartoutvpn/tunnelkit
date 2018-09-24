//
//  TunnelKitProvider+Configuration.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 10/23/17.
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
import NetworkExtension
import SwiftyBeaver

private let log = SwiftyBeaver.self

extension TunnelKitProvider {

    // MARK: Configuration
    
    /// A socket type between UDP (recommended) and TCP.
    public enum SocketType: String {

        /// UDP socket type.
        case udp = "UDP"
        
        /// TCP socket type.
        case tcp = "TCP"
    }
    
    /// Defines the communication protocol of an endpoint.
    public struct EndpointProtocol: Equatable, CustomStringConvertible {

        /// The socket type.
        public let socketType: SocketType
        
        /// The remote port.
        public let port: UInt16
        
        /// :nodoc:
        public init(_ socketType: SocketType, _ port: UInt16) {
            self.socketType = socketType
            self.port = port
        }
        
        /// :nodoc:
        public static func deserialized(_ string: String) throws -> EndpointProtocol {
            let components = string.components(separatedBy: ":")
            guard components.count == 2 else {
                throw ProviderError.configuration(field: "endpointProtocol")
            }
            guard let socketType = SocketType(rawValue: components[0]) else {
                throw ProviderError.configuration(field: "endpointProtocol.socketType")
            }
            guard let port = UInt16(components[1]) else {
                throw ProviderError.configuration(field: "endpointProtocol.port")
            }
            return EndpointProtocol(socketType, port)
        }
        
        /// :nodoc:
        public func serialized() -> String {
            return "\(socketType.rawValue):\(port)"
        }

        // MARK: Equatable
        
        /// :nodoc:
        public static func ==(lhs: EndpointProtocol, rhs: EndpointProtocol) -> Bool {
            return (lhs.socketType == rhs.socketType) && (lhs.port == rhs.port)
        }
        
        // MARK: CustomStringConvertible
        
        /// :nodoc:
        public var description: String {
            return serialized()
        }
    }

    /// Encapsulates an endpoint along with the authentication credentials.
    public struct AuthenticatedEndpoint {
        
        /// The remote hostname or IP address.
        public let hostname: String
        
        /// The username.
        public let username: String
        
        /// The password.
        public let password: String
        
        /// :nodoc:
        public init(hostname: String, username: String, password: String) {
            self.hostname = hostname
            self.username = username
            self.password = password
        }
        
        init(protocolConfiguration: NEVPNProtocol) throws {
            guard let hostname = protocolConfiguration.serverAddress else {
                throw ProviderError.configuration(field: "protocolConfiguration.serverAddress")
            }
            guard let username = protocolConfiguration.username else {
                throw ProviderError.credentials(field: "protocolConfiguration.username")
            }
            guard let passwordReference = protocolConfiguration.passwordReference else {
                throw ProviderError.credentials(field: "protocolConfiguration.passwordReference")
            }
            guard let password = try? Keychain.password(for: username, reference: passwordReference) else {
                throw ProviderError.credentials(field: "protocolConfiguration.passwordReference (keychain)")
            }
            
            self.hostname = hostname
            self.username = username
            self.password = password
        }
    }
    
    /// The way to create a `TunnelKitProvider.Configuration` object for the tunnel profile.
    public struct ConfigurationBuilder {
        
        /// Prefers resolved addresses over DNS resolution. `resolvedAddresses` must be set and non-empty. Default is `false`.
        ///
        /// - Seealso: `fallbackServerAddresses`
        public var prefersResolvedAddresses: Bool
        
        /// Resolved addresses in case DNS fails or `prefersResolvedAddresses` is `true`.
        public var resolvedAddresses: [String]?
        
        /// The accepted communication protocols. Must be non-empty.
        public var endpointProtocols: [EndpointProtocol]

        /// The encryption algorithm.
        public var cipher: SessionProxy.Cipher
        
        /// The message digest algorithm.
        public var digest: SessionProxy.Digest
        
        /// The optional CA certificate to validate server against. Set to `nil` to disable CA validation (default).
        public var ca: CryptoContainer?
        
        /// The optional client certificate to authenticate with. Set to `nil` to disable client authentication (default).
        public var clientCertificate: CryptoContainer?
        
        /// The optional key for `clientCertificate`. Set to `nil` if client authentication unused (default).
        public var clientKey: CryptoContainer?
        
        /// The MTU of the link.
        public var mtu: Int
        
        /// Sets compression framing, disabled by default.
        public var compressionFraming: SessionProxy.CompressionFraming

        /// Sends periodical keep-alive packets (ping) if set. Useful with stateful firewalls.
        public var keepAliveSeconds: Int?

        /// The number of seconds after which a renegotiation is started. Set to `nil` to disable renegotiation (default).
        public var renegotiatesAfterSeconds: Int?
        
        // MARK: Debugging
        
        /// Enables debugging. If `true`, then `debugLogKey` is a mandatory field.
        public var shouldDebug: Bool
        
        /// The key in `defaults` where the latest debug log snapshot is stored. Ignored if `shouldDebug` is `false`.
        public var debugLogKey: String?
        
        /// Optional debug log format (SwiftyBeaver format).
        public var debugLogFormat: String?
        
        // MARK: Building
        
        /**
         Default initializer.
         */
        public init() {
            prefersResolvedAddresses = false
            resolvedAddresses = nil
            endpointProtocols = [EndpointProtocol(.udp, 1194)]
            cipher = .aes128cbc
            digest = .sha1
            ca = nil
            clientCertificate = nil
            clientKey = nil
            mtu = 1500
            compressionFraming = .disabled
            keepAliveSeconds = nil
            renegotiatesAfterSeconds = nil
            shouldDebug = false
            debugLogKey = nil
            debugLogFormat = nil
        }
        
        fileprivate init(providerConfiguration: [String: Any]) throws {
            let S = Configuration.Keys.self

            guard let cipherAlgorithm = providerConfiguration[S.cipherAlgorithm] as? String, let cipher = SessionProxy.Cipher(rawValue: cipherAlgorithm) else {
                throw ProviderError.configuration(field: "protocolConfiguration.providerConfiguration[\(S.cipherAlgorithm)]")
            }
            guard let digestAlgorithm = providerConfiguration[S.digestAlgorithm] as? String, let digest = SessionProxy.Digest(rawValue: digestAlgorithm) else {
                throw ProviderError.configuration(field: "protocolConfiguration.providerConfiguration[\(S.digestAlgorithm)]")
            }

            let ca: CryptoContainer?
            let clientCertificate: CryptoContainer?
            let clientKey: CryptoContainer?
            if let pem = providerConfiguration[S.ca] as? String {
                ca = CryptoContainer(pem: pem)
            } else {
                ca = nil
            }
            if let pem = providerConfiguration[S.clientCertificate] as? String {
                guard let keyPEM = providerConfiguration[S.clientKey] as? String else {
                    throw ProviderError.configuration(field: "protocolConfiguration.providerConfiguration[\(S.clientKey)]")
                }

                clientCertificate = CryptoContainer(pem: pem)
                clientKey = CryptoContainer(pem: keyPEM)
            } else {
                clientCertificate = nil
                clientKey = nil
            }
            
            prefersResolvedAddresses = providerConfiguration[S.prefersResolvedAddresses] as? Bool ?? false
            resolvedAddresses = providerConfiguration[S.resolvedAddresses] as? [String]
            
            guard let endpointProtocolsStrings = providerConfiguration[S.endpointProtocols] as? [String], !endpointProtocolsStrings.isEmpty else {
                throw ProviderError.configuration(field: "protocolConfiguration.providerConfiguration[\(S.endpointProtocols)] is nil or empty")
            }
            endpointProtocols = try endpointProtocolsStrings.map { try EndpointProtocol.deserialized($0) }
            
            self.cipher = cipher
            self.digest = digest
            self.ca = ca
            self.clientCertificate = clientCertificate
            self.clientKey = clientKey
            mtu = providerConfiguration[S.mtu] as? Int ?? 1250
            if let compressionFramingValue = providerConfiguration[S.compressionFraming] as? Int, let compressionFraming = SessionProxy.CompressionFraming(rawValue: compressionFramingValue) {
                self.compressionFraming = compressionFraming
            } else {
                compressionFraming = .disabled
            }
            keepAliveSeconds = providerConfiguration[S.keepAlive] as? Int
            renegotiatesAfterSeconds = providerConfiguration[S.renegotiatesAfter] as? Int

            shouldDebug = providerConfiguration[S.debug] as? Bool ?? false
            if shouldDebug {
                guard let debugLogKey = providerConfiguration[S.debugLogKey] as? String else {
                    throw ProviderError.configuration(field: "protocolConfiguration.providerConfiguration[\(S.debugLogKey)]")
                }
                self.debugLogKey = debugLogKey
                debugLogFormat = providerConfiguration[S.debugLogFormat] as? String
            } else {
                debugLogKey = nil
            }

            guard !prefersResolvedAddresses || !(resolvedAddresses?.isEmpty ?? true) else {
                throw ProviderError.configuration(field: "protocolConfiguration.providerConfiguration[\(S.prefersResolvedAddresses)] is true but no [\(S.resolvedAddresses)]")
            }
        }
        
        /**
         Builds a `TunnelKitProvider.Configuration` object that will connect to the provided endpoint.
         
         - Returns: A `TunnelKitProvider.Configuration` object with this builder and the additional method parameters.
         */
        public func build() -> Configuration {
            return Configuration(
                prefersResolvedAddresses: prefersResolvedAddresses,
                resolvedAddresses: resolvedAddresses,
                endpointProtocols: endpointProtocols,
                cipher: cipher,
                digest: digest,
                ca: ca,
                clientCertificate: clientCertificate,
                clientKey: clientKey,
                mtu: mtu,
                compressionFraming: compressionFraming,
                keepAliveSeconds: keepAliveSeconds,
                renegotiatesAfterSeconds: renegotiatesAfterSeconds,
                shouldDebug: shouldDebug,
                debugLogKey: shouldDebug ? debugLogKey : nil,
                debugLogFormat: shouldDebug ? debugLogFormat : nil
            )
        }
    }
    
    /// Offers a bridge between the abstract `TunnelKitProvider.ConfigurationBuilder` and a concrete `NETunnelProviderProtocol` profile.
    public struct Configuration: Codable {
        struct Keys {
            static let appGroup = "AppGroup"
            
            static let prefersResolvedAddresses = "PrefersResolvedAddresses"

            static let resolvedAddresses = "ResolvedAddresses"

            static let endpointProtocols = "EndpointProtocols"
            
            static let cipherAlgorithm = "CipherAlgorithm"
            
            static let digestAlgorithm = "DigestAlgorithm"
            
            static let ca = "CA"
            
            static let clientCertificate = "ClientCertificate"
            
            static let clientKey = "ClientKey"
            
            static let mtu = "MTU"
            
            static let compressionFraming = "CompressionFraming"
            
            static let keepAlive = "KeepAlive"
            
            static let renegotiatesAfter = "RenegotiatesAfter"
            
            static let debug = "Debug"
            
            static let debugLogKey = "DebugLogKey"
            
            static let debugLogFormat = "DebugLogFormat"
        }
        
        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.prefersResolvedAddresses`
        public let prefersResolvedAddresses: Bool
        
        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.resolvedAddresses`
        public let resolvedAddresses: [String]?

        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.endpointProtocols`
        public let endpointProtocols: [EndpointProtocol]
        
        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.cipher`
        public let cipher: SessionProxy.Cipher
        
        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.digest`
        public let digest: SessionProxy.Digest
        
        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.ca`
        public let ca: CryptoContainer?
        
        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.clientCertificate`
        public let clientCertificate: CryptoContainer?
        
        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.clientKey`
        public let clientKey: CryptoContainer?
        
        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.mtu`
        public let mtu: Int
        
        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.compressionFraming`
        public let compressionFraming: SessionProxy.CompressionFraming
        
        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.keepAliveSeconds`
        public let keepAliveSeconds: Int?

        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.renegotiatesAfterSeconds`
        public let renegotiatesAfterSeconds: Int?
        
        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.shouldDebug`
        public let shouldDebug: Bool
        
        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.debugLogKey`
        public let debugLogKey: String?
        
        /// - Seealso: `TunnelKitProvider.ConfigurationBuilder.debugLogFormat`
        public let debugLogFormat: String?
        
        // MARK: Shortcuts

        func existingLog(in defaults: UserDefaults) -> [String]? {
            guard shouldDebug, let key = debugLogKey else {
                return nil
            }
            return defaults.array(forKey: key) as? [String]
        }
        
        // MARK: API
        
        /**
         Parses the app group from a provider configuration map.
         
         - Parameter from: The map to parse.
         - Returns: The parsed app group.
         - Throws: `ProviderError.configuration` if `providerConfiguration` does not contain an app group.
         */
        public static func appGroup(from providerConfiguration: [String: Any]) throws -> String {
            guard let appGroup = providerConfiguration[Keys.appGroup] as? String else {
                throw ProviderError.configuration(field: "protocolConfiguration.providerConfiguration[\(Keys.appGroup)]")
            }
            return appGroup
        }
        
        /**
         Parses a new `TunnelKitProvider.Configuration` object from a provider configuration map.
         
         - Parameter from: The map to parse.
         - Returns: The parsed `TunnelKitProvider.Configuration` object.
         - Throws: `ProviderError.configuration` if `providerConfiguration` is incomplete.
         */
        public static func parsed(from providerConfiguration: [String: Any]) throws -> Configuration {
            let builder = try ConfigurationBuilder(providerConfiguration: providerConfiguration)
            return builder.build()
        }
        
        /**
         Returns a dictionary representation of this configuration for use with `NETunnelProviderProtocol.providerConfiguration`.

         - Parameter appGroup: The name of the app group in which the tunnel extension lives in.
         - Returns: The dictionary representation of `self`.
         */
        public func generatedProviderConfiguration(appGroup: String) -> [String: Any] {
            let S = Keys.self
            
            var dict: [String: Any] = [
                S.appGroup: appGroup,
                S.prefersResolvedAddresses: prefersResolvedAddresses,
                S.endpointProtocols: endpointProtocols.map { $0.serialized() },
                S.cipherAlgorithm: cipher.rawValue,
                S.digestAlgorithm: digest.rawValue,
                S.mtu: mtu,
                S.debug: shouldDebug
            ]
            if let ca = ca {
                dict[S.ca] = ca.pem
            }
            if let clientCertificate = clientCertificate {
                dict[S.clientCertificate] = clientCertificate.pem
            }
            if let clientKey = clientKey {
                dict[S.clientKey] = clientKey.pem
            }
            if let resolvedAddresses = resolvedAddresses {
                dict[S.resolvedAddresses] = resolvedAddresses
            }
            dict[S.compressionFraming] = compressionFraming.rawValue
            if let keepAliveSeconds = keepAliveSeconds {
                dict[S.keepAlive] = keepAliveSeconds
            }
            if let renegotiatesAfterSeconds = renegotiatesAfterSeconds {
                dict[S.renegotiatesAfter] = renegotiatesAfterSeconds
            }
            if let debugLogKey = debugLogKey {
                dict[S.debugLogKey] = debugLogKey
            }
            if let debugLogFormat = debugLogFormat {
                dict[S.debugLogFormat] = debugLogFormat
            }
            return dict
        }
        
        /**
         Generates a `NETunnelProviderProtocol` from this configuration.
         
         - Parameter bundleIdentifier: The provider bundle identifier required to locate the tunnel extension.
         - Parameter appGroup: The name of the app group in which the tunnel extension lives in.
         - Parameter endpoint: The `TunnelKitProvider.AuthenticatedEndpoint` the tunnel will connect to.
         - Returns: The generated `NETunnelProviderProtocol` object.
         - Throws: `ProviderError.configuration` if unable to store the `endpoint.password` to the `appGroup` keychain.
         */
        public func generatedTunnelProtocol(withBundleIdentifier bundleIdentifier: String, appGroup: String, endpoint: AuthenticatedEndpoint) throws -> NETunnelProviderProtocol {
            let protocolConfiguration = NETunnelProviderProtocol()
            
            let keychain = Keychain(group: appGroup)
            do {
                try keychain.set(password: endpoint.password, for: endpoint.username, label: Bundle.main.bundleIdentifier)
            } catch _ {
                throw ProviderError.credentials(field: "keychain.set()")
            }
            
            protocolConfiguration.providerBundleIdentifier = bundleIdentifier
            protocolConfiguration.serverAddress = endpoint.hostname
            protocolConfiguration.username = endpoint.username
            protocolConfiguration.passwordReference = try? keychain.passwordReference(for: endpoint.username)
            protocolConfiguration.providerConfiguration = generatedProviderConfiguration(appGroup: appGroup)
            
            return protocolConfiguration
        }
        
        func print(appVersion: String?) {
            if let appVersion = appVersion {
                log.info("App version: \(appVersion)")
            }
            
//            log.info("\tAddress: \(endpoint.hostname):\(endpoint.port)")
            log.info("\tProtocols: \(endpointProtocols)")
            log.info("\tCipher: \(cipher)")
            log.info("\tDigest: \(digest)")
            if let _ = ca {
                log.info("\tCA verification: enabled")
            } else {
                log.info("\tCA verification: disabled")
            }
            if let _ = clientCertificate {
                log.info("\tClient verification: enabled")
            } else {
                log.info("\tClient verification: disabled")
            }
            log.info("\tMTU: \(mtu)")
            log.info("\tCompression framing: \(compressionFraming)")
            if let keepAliveSeconds = keepAliveSeconds {
                log.info("\tKeep-alive: \(keepAliveSeconds) seconds")
            } else {
                log.info("\tKeep-alive: default")
            }
            if let renegotiatesAfterSeconds = renegotiatesAfterSeconds {
                log.info("\tRenegotiation: \(renegotiatesAfterSeconds) seconds")
            } else {
                log.info("\tRenegotiation: never")
            }
            log.info("\tDebug: \(shouldDebug)")
        }
    }
}

// MARK: Modification

extension TunnelKitProvider.Configuration: Equatable {

    /**
     Returns a `TunnelKitProvider.ConfigurationBuilder` to use this configuration as a starting point for a new one.

     - Returns: An editable `TunnelKitProvider.ConfigurationBuilder` initialized with this configuration.
     */
    public func builder() -> TunnelKitProvider.ConfigurationBuilder {
        var builder = TunnelKitProvider.ConfigurationBuilder()
        builder.endpointProtocols = endpointProtocols
        builder.cipher = cipher
        builder.digest = digest
        builder.ca = ca
        builder.clientCertificate = clientCertificate
        builder.clientKey = clientKey
        builder.mtu = mtu
        builder.compressionFraming = compressionFraming
        builder.keepAliveSeconds = keepAliveSeconds
        builder.renegotiatesAfterSeconds = renegotiatesAfterSeconds
        builder.shouldDebug = shouldDebug
        builder.debugLogKey = debugLogKey
        builder.debugLogFormat = debugLogFormat
        return builder
    }

    /// :nodoc:
    public static func ==(lhs: TunnelKitProvider.Configuration, rhs: TunnelKitProvider.Configuration) -> Bool {
        return (
            (lhs.endpointProtocols == rhs.endpointProtocols) &&
            (lhs.cipher == rhs.cipher) &&
            (lhs.digest == rhs.digest) &&
            (lhs.ca == rhs.ca) &&
            (lhs.clientCertificate == rhs.clientCertificate) &&
            (lhs.clientKey == rhs.clientKey) &&
            (lhs.mtu == rhs.mtu) &&
            (lhs.compressionFraming == rhs.compressionFraming) &&
            (lhs.keepAliveSeconds == rhs.keepAliveSeconds) &&
            (lhs.renegotiatesAfterSeconds == rhs.renegotiatesAfterSeconds)
        )
    }
}

/// :nodoc:
extension TunnelKitProvider.EndpointProtocol: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let proto = try TunnelKitProvider.EndpointProtocol.deserialized(container.decode(String.self))
        self.init(proto.socketType, proto.port)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(serialized())
    }
}
