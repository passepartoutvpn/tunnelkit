//
//  CryptoCTRTests.swift
//  TunnelKitOpenVPNTests
//
//  Created by Davide De Rosa on 12/12/23.
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
@testable import TunnelKitCore
@testable import TunnelKitOpenVPNCore
import CTunnelKitCore
import CTunnelKitOpenVPNProtocol

class CryptoCTRTests: XCTestCase {
    private let cipherKey = ZeroingData(string: "aabbccddeeffaabbccddeeffaabbccddeeffaabbccddeeffaabbccddeeff", nullTerminated: false)

    private let hmacKey = ZeroingData(string: "0011223344556677001122334455667700112233445566770011223344556677", nullTerminated: false)

    func test_whenEncrypt_thenResultMatches() {
        let sut = CryptoCTR(cipherName: "aes-128-ctr", digestName: "sha256")
        sut.configureEncryption(withCipherKey: cipherKey, hmacKey: hmacKey)

        let data = Data(hex: "00112233ffddaa")
        var flags = cryptoFlags
        let expectedData = Data(hex: "52c3a656f80491ef706a3f82eb403e87552c447523fd06e472f6986f74ddf404610c86d72c68df")
        do {
            let returnedData = try sut.encryptData(data, flags: &flags)
            XCTAssertEqual(returnedData, expectedData)
        } catch {
            XCTFail("Cannot encrypt: \(error)")
        }
    }

    private var cryptoFlags: CryptoFlags {
        let packetId: [UInt8] = [0x56, 0x34, 0x12, 0x00]
        let ad: [UInt8] = [0x00, 0x12, 0x34, 0x56]
        return packetId.withUnsafeBufferPointer { (iv) in
            ad.withUnsafeBufferPointer { (ad) in
                return CryptoFlags(iv: iv.baseAddress,
                                   ivLength: packetId.count,
                                   ad: ad.baseAddress,
                                   adLength: ad.count,
                                   forTesting: true)
            }
        }
    }
}
