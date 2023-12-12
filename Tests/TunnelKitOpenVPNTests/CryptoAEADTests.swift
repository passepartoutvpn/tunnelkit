//
//  CryptoAEADTests.swift
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

class CryptoAEADTests: XCTestCase {
    private let cipherKey = ZeroingData(string: "aabbccddeeffaabbccddeeffaabbccddeeffaabbccddeeffaabbccddeeff", nullTerminated: false)

    private let hmacKey = ZeroingData(string: "0011223344556677001122334455667700112233445566770011223344556677", nullTerminated: false)

    private let plainData = Data(hex: "00112233ffddaa")

    private let encryptedData = Data(hex: "924e38066ef07f36e621a4b12322f68b4620ff9fad0c33")

    func test_givenDecrypted_whenEncrypt_thenEncrypts() {
        let sut = CryptoAEAD(cipherName: "aes-256-gcm")
        sut.configureEncryption(withCipherKey: cipherKey, hmacKey: hmacKey)

        var flags = cryptoFlags
        do {
            let returnedData = try sut.encryptData(plainData, flags: &flags)
            XCTAssertEqual(returnedData, encryptedData)
        } catch {
            XCTFail("Cannot encrypt: \(error)")
        }
    }

    func test_givenEncrypted_whenDecrypt_thenDecrypts() {
        let sut = CryptoAEAD(cipherName: "aes-256-gcm")
        sut.configureDecryption(withCipherKey: cipherKey, hmacKey: hmacKey)

        var flags = cryptoFlags
        do {
            let returnedData = try sut.decryptData(encryptedData, flags: &flags)
            XCTAssertEqual(returnedData, plainData)
        } catch {
            XCTFail("Cannot decrypt: \(error)")
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
