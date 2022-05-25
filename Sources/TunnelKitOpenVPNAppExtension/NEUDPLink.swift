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
    let xorMethod: Int
    
    init(impl: NWUDPSession, maxDatagrams: Int? = nil, xorMask: Data?, xorMethod: Int?) {
        self.impl = impl
        self.maxDatagrams = maxDatagrams ?? 200
        self.xorMask = xorMask ?? Data(repeating: 0, count: 1)
        self.xorMethod = xorMethod ?? 0
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
            if let packets = packets, self.xorMethod != 0 {
                packetsToUse = packets.map { packet in
                    self.xorPacket(packet: packet, mode: .read)
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
        let dataToUse: Data = xorPacket(packet: packet, mode: .write)
        impl.writeDatagram(dataToUse) { error in
            completionHandler?(error)
        }
    }
    
    func writePackets(_ packets: [Data], completionHandler: ((Error?) -> Void)?) {
        var packetsToUse: [Data]
        if xorMethod != 0 {
            packetsToUse = packets.map { packet in
                xorPacket(packet: packet, mode: .write)
            }
        } else {
            packetsToUse = packets
        }
        impl.writeMultipleDatagrams(packetsToUse) { error in
            completionHandler?(error)
        }
    }
    
    private func xorPacket(packet: Data, mode: Mode) -> Data {
        switch xorMethod {
        case 0:
            return packet
        case 1:
            return xormask(packet: packet)
        case 2:
            return xorptrpos(packet: packet)
        case 3:
            return reverse(packet: packet)
        case 4:
            if mode == .read {
                return xorptrpos(packet: reverse(packet: xorptrpos(packet: xormask(packet: packet))))
            } else {
                return xormask(packet: xorptrpos(packet: reverse(packet: xorptrpos(packet: packet))))
            }
        default:
            return packet
        }
    }
    
    private func xormask(packet: Data) -> Data {
        if xorMask.count == 0 {
            return packet
        }
        return Data(packet.enumerated().map { (index, byte) in
            byte ^ [UInt8](self.xorMask)[index % self.xorMask.count]
        })
    }
    
    private func xorptrpos(packet: Data) -> Data {
        return Data(packet.enumerated().map { (index, byte) in
            byte ^ UInt8(truncatingIfNeeded: index &+ 1)
        })
    }
    
    private func reverse(packet: Data) -> Data {
        Data(([UInt8](packet))[0..<1] + ([UInt8](packet)[1...]).reversed())
    }
}

extension NEUDPSocket: LinkProducer {
    public func link(xorMask: Data?, xorMethod: Int?) -> LinkInterface {
        return NEUDPLink(impl: impl, maxDatagrams: nil, xorMask: xorMask, xorMethod: xorMethod)
    }
}
