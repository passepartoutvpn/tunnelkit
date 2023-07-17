//
//  XORProcessor.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 11/4/22.
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
import TunnelKitOpenVPNCore

/// Processes data packets according to a XOR method.
public struct XORProcessor {
    private let method: OpenVPN.XORMethod?

    public init(method: OpenVPN.XORMethod?) {
        self.method = method
    }

    /**
     Returns an array of data packets processed according to XOR method.
     
     - Parameter packets: The array of packets.
     - Parameter outbound: Set `true` if packets are outbound, `false` otherwise.
     - Returns: The array of packets after XOR processing.
     **/
    public func processPackets(_ packets: [Data], outbound: Bool) -> [Data] {
        guard let _ = method else {
            return packets
        }
        return packets.map {
            processPacket($0, outbound: outbound)
        }
    }

    /**
     Returns a data packet processed according to XOR method.
     
     - Parameter packets: The packet.
     - Parameter outbound: Set `true` if packet is outbound, `false` otherwise.
     - Returns: The packet after XOR processing.
     **/
    public func processPacket(_ packet: Data, outbound: Bool) -> Data {
        guard let method = method else {
            return packet
        }
        switch method {
        case .xormask(let mask):
            return Self.xormask(packet: packet, mask: mask)

        case .xorptrpos:
            return Self.xorptrpos(packet: packet)

        case .reverse:
            return Self.reverse(packet: packet)

        case .obfuscate(let mask):
            if outbound {
                return Self.xormask(packet: Self.xorptrpos(packet: Self.reverse(packet: Self.xorptrpos(packet: packet))), mask: mask)
            } else {
                return Self.xorptrpos(packet: Self.reverse(packet: Self.xorptrpos(packet: Self.xormask(packet: packet, mask: mask))))
            }
        }
    }
}

extension XORProcessor {
    private static func xormask(packet: Data, mask: Data) -> Data {
        Data(packet.enumerated().map { (index, byte) in
            byte ^ [UInt8](mask)[index % mask.count]
        })
    }

    private static func xorptrpos(packet: Data) -> Data {
        Data(packet.enumerated().map { (index, byte) in
            byte ^ UInt8(truncatingIfNeeded: index &+ 1)
        })
    }

    private static func reverse(packet: Data) -> Data {
        Data(([UInt8](packet))[0..<1] + ([UInt8](packet)[1...]).reversed())
    }
}
