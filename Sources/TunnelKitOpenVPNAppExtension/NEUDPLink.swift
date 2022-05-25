//
//  NEUDPLink.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 5/23/19.
//  Copyright (c) 2022 Davide De Rosa. All rights reserved.
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
import NetworkExtension
import TunnelKitCore
import TunnelKitAppExtension

class NEUDPLink: LinkInterface {
    private let impl: NWUDPSession
    
    private let maxDatagrams: Int
    
    let xorMask: Data
    
    init(impl: NWUDPSession, maxDatagrams: Int? = nil, xorMask: Data?) {
        self.impl = impl
        self.maxDatagrams = maxDatagrams ?? 200
        self.xorMask = xorMask ?? Data(repeating: 0, count: 1)
    }
    
    // MARK: LinkInterface
    
    let isReliable: Bool = false
    
    var remoteAddress: String? {
        return (impl.resolvedEndpoint as? NWHostEndpoint)?.hostname
    }
    
    var packetBufferSize: Int {
        return maxDatagrams
    }
    
    func setReadHandler(queue: DispatchQueue, _ handler: @escaping ([Data]?, Error?) -> Void) {
        
        // WARNING: runs in Network.framework queue
        impl.setReadHandler({ [weak self] packets, error in
            guard let self = self else {
                return
            }
            var packetsToUse: [Data]?
            if let packets = packets, [UInt8](self.xorMask)[0] != 0 {
                packetsToUse = packets.map { packet in
                    self.xorPacket(packet: packet)
                }
            } else {
                packetsToUse = packets
            }
            queue.sync {
                handler(packetsToUse, error)
            }
        }, maxDatagrams: maxDatagrams)
    }
    
    func writePacket(_ packet: Data, completionHandler: ((Error?) -> Void)?) {
        let dataToUse: Data = xorPacket(packet: packet)
        impl.writeDatagram(dataToUse) { error in
            completionHandler?(error)
        }
    }
    
    func writePackets(_ packets: [Data], completionHandler: ((Error?) -> Void)?) {
        var packetsToUse: [Data]
        if [UInt8](xorMask)[0] != 0 {
            packetsToUse = packets.map { packet in
                xorPacket(packet: packet)
            }
        } else {
            packetsToUse = packets
        }
        impl.writeMultipleDatagrams(packetsToUse) { error in
            completionHandler?(error)
        }
    }
    
    private func xorPacket(packet: Data) -> Data {
        if [UInt8](xorMask)[0] != 0 {
            return packet
        }
        return Data(packet.enumerated().map { (index, byte) in
            byte ^ [UInt8](self.xorMask)[index % self.xorMask.count]
        })
    }
}

extension NEUDPSocket: LinkProducer {
    public func link(xorMask: Data?) -> LinkInterface {
        return NEUDPLink(impl: impl, maxDatagrams: nil, xorMask: xorMask)
    }
}
