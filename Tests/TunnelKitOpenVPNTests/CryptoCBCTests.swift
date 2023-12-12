//
//  CryptoCBCTests.swift
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

class CryptoCBCTests: XCTestCase {
    private let cipherKey = ZeroingData(string: "aabbccddeeffaabbccddeeffaabbccddeeffaabbccddeeffaabbccddeeff", nullTerminated: false)

    private let hmacKey = ZeroingData(string: "0011223344556677001122334455667700112233445566770011223344556677", nullTerminated: false)

    private let plainData = Data(hex: "00112233ffddaa")

    private let plainHMACData = Data(hex: "1d7c9d9d5aa411d18a8416e10a3c8f13c6e6941eeb3b81698496be034bf5113600112233ffddaa")

    private let encryptedHMACData = Data(hex: "24be983962e4b4aeacb5734522e37f90f6669e0cfd7f8ab962587dc97d1f600e000000000000000000000000000000003c76480bad5e953ca1211ef83f5594c6")

    func test_givenDecrypted_whenEncryptWithoutCipher_thenEncodesWithHMAC() {
        let sut = CryptoCBC(cipherName: nil, digestName: "sha256")
        sut.configureEncryption(withCipherKey: nil, hmacKey: hmacKey)

        var flags = cryptoFlags
        do {
            let returnedData = try sut.encryptData(plainData, flags: &flags)
            XCTAssertEqual(returnedData, plainHMACData)
        } catch {
            XCTFail("Cannot encrypt: \(error)")
        }
    }

    func test_givenDecrypted_whenEncryptWithCipher_thenEncryptsWithHMAC() {
        let sut = CryptoCBC(cipherName: "aes-128-cbc", digestName: "sha256")
        sut.configureEncryption(withCipherKey: cipherKey, hmacKey: hmacKey)

        var flags = cryptoFlags
        do {
            let returnedData = try sut.encryptData(plainData, flags: &flags)
            XCTAssertEqual(returnedData, encryptedHMACData)
        } catch {
            XCTFail("Cannot encrypt: \(error)")
        }
    }

    func test_givenEncodedWithHMAC_thenDecodes() {
        let sut = CryptoCBC(cipherName: nil, digestName: "sha256")
        sut.configureDecryption(withCipherKey: nil, hmacKey: hmacKey)

        var flags = cryptoFlags
        do {
            let returnedData = try sut.decryptData(plainHMACData, flags: &flags)
            XCTAssertEqual(returnedData, plainData)
        } catch {
            XCTFail("Cannot decrypt: \(error)")
        }
    }

    func test_givenEncryptedWithHMAC_thenDecrypts() {
        let sut = CryptoCBC(cipherName: "aes-128-cbc", digestName: "sha256")
        sut.configureDecryption(withCipherKey: cipherKey, hmacKey: hmacKey)

        var flags = cryptoFlags
        do {
            let returnedData = try sut.decryptData(encryptedHMACData, flags: &flags)
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
