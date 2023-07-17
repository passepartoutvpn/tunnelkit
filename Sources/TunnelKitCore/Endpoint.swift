//
//  Endpoint.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 11/10/18.
//  Copyright (c) 2023 Davide De Rosa. All rights reserved.
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
import __TunnelKitUtils

/// Represents an endpoint.
public struct Endpoint: RawRepresentable, Codable, Equatable, CustomStringConvertible {

    // XXX: simplistic match
    private static let rx = NSRegularExpression("^([^\\s]+):(UDP[46]?|TCP[46]?):(\\d+)$")

    public let address: String

    public let proto: EndpointProtocol

    public init(_ address: String, _ proto: EndpointProtocol) {
        self.address = address
        self.proto = proto
    }

    public var isIPv4: Bool {
        var addr = in_addr()
        let result = address.withCString {
            inet_pton(AF_INET, $0, &addr)
        }
        return result > 0
    }

    public var isIPv6: Bool {
        var addr = in_addr()
        let result = address.withCString {
            inet_pton(AF_INET6, $0, &addr)
        }
        return result > 0
    }

    public var isHostname: Bool {
        !isIPv4 && !isIPv6
    }

    public func withRandomPrefixLength(_ length: Int) throws -> Endpoint {
        guard isHostname else {
            return self
        }
        let prefix = try SecureRandom.data(length: length)
        let prefixedAddress = "\(prefix.toHex()).\(address)"
        return Endpoint(prefixedAddress, proto)
    }

    // MARK: RawRepresentable

    public init?(rawValue: String) {
        let components = Self.rx.groups(in: rawValue)
        guard components.count == 3 else {
            return nil
        }
        let address = components[0]
        guard let socketType = SocketType(rawValue: components[1]) else {
            return nil
        }
        guard let port = UInt16(components[2]) else {
            return nil
        }
        self.init(address, EndpointProtocol(socketType, port))
    }

    public var rawValue: String {
        "\(address):\(proto.socketType.rawValue):\(proto.port)"
    }

    // MARK: CustomStringConvertible

    public var description: String {
        "\(address.maskedDescription):\(proto.rawValue)"
    }
}

/// Defines the communication protocol of an endpoint.
public struct EndpointProtocol: RawRepresentable, Equatable, CustomStringConvertible {

    /// The socket type.
    public let socketType: SocketType

    /// The remote port.
    public let port: UInt16

    public init(_ socketType: SocketType, _ port: UInt16) {
        self.socketType = socketType
        self.port = port
    }

    // MARK: RawRepresentable

    public init?(rawValue: String) {
        let components = rawValue.components(separatedBy: ":")
        guard components.count == 2 else {
            return nil
        }
        guard let socketType = SocketType(rawValue: components[0]) else {
            return nil
        }
        guard let port = UInt16(components[1]) else {
            return nil
        }
        self.init(socketType, port)
    }

    public var rawValue: String {
        "\(socketType.rawValue):\(port)"
    }

    // MARK: CustomStringConvertible

    public var description: String {
        rawValue
    }
}

extension EndpointProtocol: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        let proto = EndpointProtocol(rawValue: rawValue) ?? EndpointProtocol(.udp, 1198)
        self.init(proto.socketType, proto.port)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
