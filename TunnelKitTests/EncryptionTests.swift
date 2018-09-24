//
//  EncryptionTests.swift
//  TunnelKitTests
//
//  Created by Davide De Rosa on 7/7/18.
//  Copyright (c) 2018 Davide De Rosa. All rights reserved.
//
//  https://github.com/keeshux
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
//  This file incorporates work covered by the following copyright and
//  permission notice:
//
//      Copyright (c) 2018-Present Private Internet Access
//
//      Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//      The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//      THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//
//

import XCTest
@testable import TunnelKit
@testable import __TunnelKitNative

class EncryptionTests: XCTestCase {
    private var cipherEncKey: ZeroingData!

    private var cipherDecKey: ZeroingData!
    
    private var hmacEncKey: ZeroingData!
    
    private var hmacDecKey: ZeroingData!
    
    override func setUp() {
        cipherEncKey = try! SecureRandom.safeData(length: 32)
        cipherDecKey = try! SecureRandom.safeData(length: 32)
        hmacEncKey = try! SecureRandom.safeData(length: 32)
        hmacDecKey = try! SecureRandom.safeData(length: 32)
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testCBC() {
        let (client, server) = clientServer("aes-128-cbc", "sha256")

        let plain = Data(hex: "00112233445566778899")
        let encrypted = try! client.encrypter().encryptData(plain, extra: nil)
        let decrypted = try! server.decrypter().decryptData(encrypted, extra: nil)
        XCTAssertEqual(plain, decrypted)
    }

    func testHMAC() {
        let (client, server) = clientServer(nil, "sha256")

        let plain = Data(hex: "00112233445566778899")
        let encrypted = try! client.encrypter().encryptData(plain, extra: nil)
        XCTAssertNoThrow(try server.decrypter().verifyData(encrypted, extra: nil))
    }
    
    func testGCM() {
        let (client, server) = clientServer("aes-256-gcm", nil)
        
//        let packetId: UInt32 = 0x56341200
        let extra: [UInt8] = [0x00, 0x12, 0x34, 0x56]
        let plain = Data(hex: "00112233445566778899")
        let encrypted = try! client.encrypter().encryptData(plain, extra: extra)
        let decrypted = try! server.decrypter().decryptData(encrypted, extra: extra)
        XCTAssertEqual(plain, decrypted)
    }

    private func clientServer(_ c: String?, _ d: String?) -> (CryptoBox, CryptoBox) {
        let client = CryptoBox(cipherAlgorithm: c, digestAlgorithm: d)
        let server = CryptoBox(cipherAlgorithm: c, digestAlgorithm: d)
        XCTAssertNoThrow(try client.configure(withCipherEncKey: cipherEncKey, cipherDecKey: cipherDecKey, hmacEncKey: hmacEncKey, hmacDecKey: hmacDecKey))
        XCTAssertNoThrow(try server.configure(withCipherEncKey: cipherDecKey, cipherDecKey: cipherEncKey, hmacEncKey: hmacDecKey, hmacDecKey: hmacEncKey))
        return (client, server)
    }
}
