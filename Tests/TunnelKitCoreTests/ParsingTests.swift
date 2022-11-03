//
//  ParsingTests.swift
//  TunnelKitCoreTests
//
//  Created by Davide De Rosa on 10/25/22.
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

import XCTest
@testable import TunnelKitCore

class ParsingTests: XCTestCase {

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testEndpointV4() {
        let ipAddress = "1.2.3.4"
        let socketType = "TCP"
        let port = 1194
        guard let endpoint = Endpoint(rawValue: "\(ipAddress):\(socketType):\(port)") else {
            XCTFail()
            return
        }
        XCTAssertEqual(endpoint.address, ipAddress)
        XCTAssertEqual(endpoint.proto.socketType.rawValue, socketType)
        XCTAssertEqual(endpoint.proto.port, UInt16(port))
    }

    func testEndpointV6() {
        let ipAddress = "2607:f0d0:1002:51::4"
        let socketType = "TCP"
        let port = 1194
        guard let endpoint = Endpoint(rawValue: "\(ipAddress):\(socketType):\(port)") else {
            XCTFail()
            return
        }
        XCTAssertEqual(endpoint.address, ipAddress)
        XCTAssertEqual(endpoint.proto.socketType.rawValue, socketType)
        XCTAssertEqual(endpoint.proto.port, UInt16(port))
    }
}
