//
//  XORTests.swift
//  TunnelKitOpenVPNTests
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

import XCTest
import TunnelKitCore
import TunnelKitOpenVPNProtocol
import CTunnelKitOpenVPNProtocol

final class XORTests: XCTestCase {
    private let mask = Data(hex: "f76dab30")

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testMask() throws {
        let processor = XORProcessor(method: .xormask(mask: mask))
        processor.assertReversible(try SecureRandom.data(length: 1000))
    }

    func testPtrPos() throws {
        let processor = XORProcessor(method: .xorptrpos)
        processor.assertReversible(try SecureRandom.data(length: 1000))
    }

    func testReverse() throws {
        let processor = XORProcessor(method: .reverse)
        processor.assertReversible(try SecureRandom.data(length: 1000))
    }

    func testObfuscate() throws {
        let processor = XORProcessor(method: .obfuscate(mask: mask))
        processor.assertReversible(try SecureRandom.data(length: 1000))
    }

    func testPacketStream() throws {
        let data = try SecureRandom.data(length: 10000)
        PacketStream.assertReversible(data, method: .none)
        PacketStream.assertReversible(data, method: .mask, mask: mask)
        PacketStream.assertReversible(data, method: .ptrPos)
        PacketStream.assertReversible(data, method: .reverse)
        PacketStream.assertReversible(data, method: .obfuscate, mask: mask)
    }
}

private extension XORProcessor {
    func assertReversible(_ data: Data) {
        let xored = processPacket(data, outbound: true)
        XCTAssertEqual(processPacket(xored, outbound: false), data)
    }
}

private extension PacketStream {
    static func assertReversible(_ data: Data, method: XORMethodNative, mask: Data? = nil) {
        var until = 0
        let outStream = PacketStream.outboundStream(fromPacket: data, xorMethod: method, xorMask: mask)
        let inStream = PacketStream.packets(fromInboundStream: outStream, until: &until, xorMethod: method, xorMask: mask)
        let originalData = Data(inStream.joined())
        XCTAssertEqual(data.toHex(), originalData.toHex())
    }
}
