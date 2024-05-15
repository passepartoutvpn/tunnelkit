//
//  Configuration.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 11/23/21.
//  Copyright (c) 2024 Davide De Rosa. All rights reserved.
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
import NetworkExtension

public protocol WireGuardConfigurationProviding {
    var interface: InterfaceConfiguration { get }

    var peers: [PeerConfiguration] { get }

    var privateKey: String { get }

    var publicKey: String { get }

    var addresses: [String] { get }

    var dnsServers: [String] { get }

    var dnsSearchDomains: [String] { get }

    var mtu: UInt16? { get }

    var peersCount: Int { get }

    func publicKey(ofPeer peerIndex: Int) -> String

    func preSharedKey(ofPeer peerIndex: Int) -> String?

    func endpoint(ofPeer peerIndex: Int) -> String?

    func allowedIPs(ofPeer peerIndex: Int) -> [String]

    func keepAlive(ofPeer peerIndex: Int) -> UInt16?
}

extension WireGuard {
    public struct ConfigurationBuilder: WireGuardConfigurationProviding {
        private static let defaultGateway4 = IPAddressRange(from: "0.0.0.0/0")!

        private static let defaultGateway6 = IPAddressRange(from: "::/0")!

        public private(set) var interface: InterfaceConfiguration

        public private(set) var peers: [PeerConfiguration]

        public init() {
            self.init(PrivateKey())
        }

        public init(_ base64PrivateKey: String) throws {
            guard let privateKey = PrivateKey(base64Key: base64PrivateKey) else {
                throw WireGuard.ConfigurationError.interfaceHasInvalidPrivateKey(base64PrivateKey)
            }
            self.init(privateKey)
        }

        private init(_ privateKey: PrivateKey) {
            interface = InterfaceConfiguration(privateKey: privateKey)
            peers = []
        }

        public init(_ tunnelConfiguration: TunnelConfiguration) {
            interface = tunnelConfiguration.interface
            peers = tunnelConfiguration.peers
        }

        // MARK: WireGuardConfigurationProviding

        public var privateKey: String {
            get {
                interface.privateKey.base64Key
            }
            set {
                guard let key = PrivateKey(base64Key: newValue) else {
                    return
                }
                interface.privateKey = key
            }
        }

        public var addresses: [String] {
            get {
                interface.addresses.map(\.stringRepresentation)
            }
            set {
                interface.addresses = newValue.compactMap(IPAddressRange.init)
            }
        }

        public var dnsServers: [String] {
            get {
                interface.dns.map(\.stringRepresentation)
            }
            set {
                interface.dns = newValue.compactMap(DNSServer.init)
            }
        }

        public var dnsSearchDomains: [String] {
            get {
                interface.dnsSearch
            }
            set {
                interface.dnsSearch = newValue
            }
        }

        public var mtu: UInt16? {
            get {
                interface.mtu
            }
            set {
                interface.mtu = newValue
            }
        }

        // MARK: Modification

        public mutating func addPeer(_ base64PublicKey: String, endpoint: String, allowedIPs: [String] = []) throws {
            guard let publicKey = PublicKey(base64Key: base64PublicKey) else {
                throw WireGuard.ConfigurationError.peerHasInvalidPublicKey(base64PublicKey)
            }
            var peer = PeerConfiguration(publicKey: publicKey)
            peer.endpoint = Endpoint(from: endpoint)
            peer.allowedIPs = allowedIPs.compactMap(IPAddressRange.init)
            peers.append(peer)
        }

        public mutating func setPreSharedKey(_ base64Key: String, ofPeer peerIndex: Int) throws {
            guard let preSharedKey = PreSharedKey(base64Key: base64Key) else {
                throw WireGuard.ConfigurationError.peerHasInvalidPreSharedKey(base64Key)
            }
            peers[peerIndex].preSharedKey = preSharedKey
        }

        public mutating func addDefaultGatewayIPv4(toPeer peerIndex: Int) {
            peers[peerIndex].allowedIPs.append(Self.defaultGateway4)
        }

        public mutating func addDefaultGatewayIPv6(toPeer peerIndex: Int) {
            peers[peerIndex].allowedIPs.append(Self.defaultGateway6)
        }

        public mutating func removeDefaultGatewayIPv4(fromPeer peerIndex: Int) {
            peers[peerIndex].allowedIPs.removeAll {
                $0 == Self.defaultGateway4
            }
        }

        public mutating func removeDefaultGatewayIPv6(fromPeer peerIndex: Int) {
            peers[peerIndex].allowedIPs.removeAll {
                $0 == Self.defaultGateway6
            }
        }

        public mutating func removeDefaultGateways(fromPeer peerIndex: Int) {
            peers[peerIndex].allowedIPs.removeAll {
                $0 == Self.defaultGateway4 || $0 == Self.defaultGateway6
            }
        }

        public mutating func removeAllDefaultGateways() {
            peers.indices.forEach {
                removeDefaultGateways(fromPeer: $0)
            }
        }

        public mutating func addAllowedIP(_ allowedIP: String, toPeer peerIndex: Int) {
            guard let addr = IPAddressRange(from: allowedIP) else {
                return
            }
            peers[peerIndex].allowedIPs.append(addr)
        }

        public mutating func removeAllowedIP(_ allowedIP: String, fromPeer peerIndex: Int) {
            guard let addr = IPAddressRange(from: allowedIP) else {
                return
            }
            peers[peerIndex].allowedIPs.removeAll {
                $0 == addr
            }
        }

        public mutating func setKeepAlive(_ keepAlive: UInt16, forPeer peerIndex: Int) {
            peers[peerIndex].persistentKeepAlive = keepAlive
        }

        public func build() -> Configuration {
            let tunnelConfiguration = TunnelConfiguration(name: nil, interface: interface, peers: peers)
            return Configuration(tunnelConfiguration: tunnelConfiguration)
        }
    }

    public struct Configuration: Codable, Equatable, WireGuardConfigurationProviding {
        public let tunnelConfiguration: TunnelConfiguration

        public var interface: InterfaceConfiguration {
            tunnelConfiguration.interface
        }

        public var peers: [PeerConfiguration] {
            tunnelConfiguration.peers
        }

        public init(tunnelConfiguration: TunnelConfiguration) {
            self.tunnelConfiguration = tunnelConfiguration
        }

        public func builder() -> WireGuard.ConfigurationBuilder {
            WireGuard.ConfigurationBuilder(tunnelConfiguration)
        }

        // MARK: WireGuardConfigurationProviding

        public var privateKey: String {
            interface.privateKey.base64Key
        }

        public var publicKey: String {
            interface.privateKey.publicKey.base64Key
        }

        public var addresses: [String] {
            interface.addresses.map(\.stringRepresentation)
        }

        public var dnsServers: [String] {
            interface.dns.map(\.stringRepresentation)
        }

        public var dnsSearchDomains: [String] {
            interface.dnsSearch
        }

        public var mtu: UInt16? {
            interface.mtu
        }

        // MARK: Codable

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let wg = try container.decode(String.self)
            let cfg = try TunnelConfiguration(fromWgQuickConfig: wg, called: nil)
            self.init(tunnelConfiguration: cfg)
        }

        public func encode(to encoder: Encoder) throws {
            let wg = tunnelConfiguration.asWgQuickConfig()
            var container = encoder.singleValueContainer()
            try container.encode(wg)
        }
    }
}

extension WireGuardConfigurationProviding {
    public var publicKey: String {
        interface.privateKey.publicKey.base64Key
    }

    public var peersCount: Int {
        peers.count
    }

    public func publicKey(ofPeer peerIndex: Int) -> String {
        peers[peerIndex].publicKey.base64Key
    }

    public func preSharedKey(ofPeer peerIndex: Int) -> String? {
        peers[peerIndex].preSharedKey?.base64Key
    }

    public func endpoint(ofPeer peerIndex: Int) -> String? {
        peers[peerIndex].endpoint?.stringRepresentation
    }

    public func allowedIPs(ofPeer peerIndex: Int) -> [String] {
        peers[peerIndex].allowedIPs.map(\.stringRepresentation)
    }

    public func keepAlive(ofPeer peerIndex: Int) -> UInt16? {
        peers[peerIndex].persistentKeepAlive
    }
}
