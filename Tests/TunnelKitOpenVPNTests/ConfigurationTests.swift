//
//  ConfigurationTests.swift
//  TunnelKitOpenVPNTests
//
//  Created by Davide De Rosa on 10/17/22.
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
import TunnelKitOpenVPNCore

class ConfigurationTests: XCTestCase {
    override func setUp() {
        super.setUp()

        CoreConfiguration.masksPrivateData = false
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testRandomizeHostnames() {
        var builder = OpenVPN.ConfigurationBuilder()
        let hostname = "my.host.name"
        let ipv4 = "1.2.3.4"
        builder.remotes = [
            .init(hostname, .init(.udp, 1111)),
            .init(ipv4, .init(.udp4, 3333))
        ]
        builder.randomizeHostnames = true
        let cfg = builder.build()

        cfg.processedRemotes?.forEach {
            let comps = $0.address.components(separatedBy: ".")
            guard let first = comps.first else {
                XCTFail()
                return
            }
            if $0.isHostname {
                XCTAssert($0.address.hasSuffix(hostname))
                XCTAssert(first.count == 12)
                XCTAssert(first.allSatisfy {
                    "0123456789abcdef".contains($0)
                })
            } else {
                XCTAssert($0.address == ipv4)
            }
        }
    }
}
