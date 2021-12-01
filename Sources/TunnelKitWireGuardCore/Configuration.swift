//
//  Configuration.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 11/23/21.
//  Copyright (c) 2021 Davide De Rosa. All rights reserved.
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

import Foundation
import WireGuardKit

extension WireGuard {
    public struct ConfigurationBuilder {
        public var privateKey: String?
        
        public var addresses: [String]?
        
        public var dns: [String]?

        public var mtu: UInt16?
        
        public var peerPublicKey: String?
        
        public var peerPreSharedKey: String?

        public var peerAddress: String?

        public var peerPort: UInt16?
        
        public var allowedIPs: [String]?
        
        public var keepAliveInterval: UInt16?
        
        public init() {
        }

        public func build() -> Configuration? {
            guard let privateKey = privateKey, let clientPrivateKey = PrivateKey(base64Key: privateKey) else {
                return nil
            }
            guard let peerPublicKey = peerPublicKey, let serverPublicKey = PublicKey(base64Key: peerPublicKey) else {
                return nil
            }
            guard let peerAddress = peerAddress, let peerPort = peerPort, let endpoint = Endpoint(from: "\(peerAddress):\(peerPort)") else {
                  return nil
            }

            var interfaceConfiguration = InterfaceConfiguration(privateKey: clientPrivateKey)
            if let clientAddresses = addresses?.mapOptional({ IPAddressRange(from: $0) }) {
                interfaceConfiguration.addresses = clientAddresses
            }
            if let dnsServers = dns?.mapOptional({ DNSServer(from: $0) }) {
                interfaceConfiguration.dns = dnsServers
            }
            interfaceConfiguration.mtu = mtu
            var peerConfiguration = PeerConfiguration(publicKey: serverPublicKey)
            if let peerPreSharedKey = peerPreSharedKey {
                peerConfiguration.preSharedKey = PreSharedKey(base64Key: peerPreSharedKey)
            }
            if let peerAllowedIPs = allowedIPs?.mapOptional({ IPAddressRange(from: $0) }) {
                peerConfiguration.allowedIPs = peerAllowedIPs
            }
            peerConfiguration.endpoint = endpoint
            peerConfiguration.persistentKeepAlive = keepAliveInterval

            let tunnelConfiguration = TunnelConfiguration(name: nil, interface: interfaceConfiguration, peers: [peerConfiguration])
            return Configuration(tunnelConfiguration: tunnelConfiguration)
        }
    }

    public struct Configuration {
        public let tunnelConfiguration: TunnelConfiguration
    }
}

private extension Array {
    func mapOptional<V>(_ transform: (Self.Element) throws -> V?) rethrows -> [V] {
        return try map(transform)
            .filter { $0 != nil }
            .map { $0! }
    }
}
