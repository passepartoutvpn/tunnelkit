//
//  DNSTests.swift
//  TunnelKitTests
//
//  Created by Davide De Rosa on 8/31/18.
//  Copyright (c) 2020 Davide De Rosa. All rights reserved.
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
import TunnelKit
import __TunnelKitCore

class DNSTests: XCTestCase {

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testIPv4() {
        let addr = "1.2.3.4"
        let ip: UInt32 = 0x01020304
        
        XCTAssertEqual(DNSResolver.ipv4(fromString: addr), ip)
        XCTAssertEqual(DNSResolver.string(fromIPv4: ip), addr)

        XCTAssertEqual(DNSResolver.string(fromIPv4: DNSResolver.ipv4(fromString: addr)!), addr)
        XCTAssertEqual(DNSResolver.ipv4(fromString: DNSResolver.string(fromIPv4: ip)), ip)
    }
    
    func testSystem() {
        print("DNS: \(DNS().systemServers())")
    }
}
