//
//  AppExtensionTests.swift
//  TunnelKitTests
//
//  Created by Davide De Rosa on 10/23/17.
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

import XCTest
@testable import TunnelKit
import NetworkExtension

class AppExtensionTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testConfiguration() {
        var builder: OpenVPNTunnelProvider.ConfigurationBuilder!
        var cfg: OpenVPNTunnelProvider.Configuration!

        let identifier = "com.example.Provider"
        let appGroup = "group.com.algoritmico.TunnelKit"
        let hostname = "example.com"
        let credentials = OpenVPN.Credentials("foo", "bar")

        var sessionBuilder = OpenVPN.ConfigurationBuilder()
        sessionBuilder.ca = OpenVPN.CryptoContainer(pem: "abcdef")
        sessionBuilder.cipher = .aes128cbc
        sessionBuilder.digest = .sha256
        sessionBuilder.hostname = hostname
        sessionBuilder.endpointProtocols = []
        builder = OpenVPNTunnelProvider.ConfigurationBuilder(sessionConfiguration: sessionBuilder.build())
        XCTAssertNotNil(builder)

        cfg = builder.build()

        let proto = try? cfg.generatedTunnelProtocol(withBundleIdentifier: identifier, appGroup: appGroup, credentials: credentials)
        XCTAssertNotNil(proto)
        
        XCTAssertEqual(proto?.providerBundleIdentifier, identifier)
        XCTAssertEqual(proto?.serverAddress, hostname)
        XCTAssertEqual(proto?.username, credentials.username)
        XCTAssertEqual(proto?.passwordReference, try? Keychain(group: appGroup).passwordReference(for: credentials.username))

        if let pc = proto?.providerConfiguration {
            print("\(pc)")
        }
        
        let K = OpenVPNTunnelProvider.Configuration.Keys.self
        XCTAssertEqual(proto?.providerConfiguration?[K.appGroup] as? String, appGroup)
        XCTAssertEqual(proto?.providerConfiguration?[K.cipherAlgorithm] as? String, cfg.sessionConfiguration.cipher?.rawValue)
        XCTAssertEqual(proto?.providerConfiguration?[K.digestAlgorithm] as? String, cfg.sessionConfiguration.digest?.rawValue)
        XCTAssertEqual(proto?.providerConfiguration?[K.ca] as? String, cfg.sessionConfiguration.ca?.pem)
        XCTAssertEqual(proto?.providerConfiguration?[K.mtu] as? Int, cfg.mtu)
        XCTAssertEqual(proto?.providerConfiguration?[K.renegotiatesAfter] as? TimeInterval, cfg.sessionConfiguration.renegotiatesAfter)
        XCTAssertEqual(proto?.providerConfiguration?[K.debug] as? Bool, cfg.shouldDebug)
    }
    
    func testDNSResolver() {
        let exp = expectation(description: "DNS")
        DNSResolver.resolve("djsbjhcbjzhbxjnvsd.com", timeout: 1000, queue: DispatchQueue.main) { (addrs, error) in
            defer {
                exp.fulfill()
            }
            guard let addrs = addrs else {
                print("Can't resolve")
                return
            }
            print("\(addrs)")
        }
        waitForExpectations(timeout: 5.0, handler: nil)
    }
}
