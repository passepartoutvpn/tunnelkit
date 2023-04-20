//
//  AppExtensionTests.swift
//  TunnelKitOpenVPNTests
//
//  Created by Davide De Rosa on 10/23/17.
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
import NetworkExtension
import TunnelKitCore
import TunnelKitOpenVPNCore
import TunnelKitAppExtension
@testable import TunnelKitOpenVPNAppExtension
import TunnelKitManager
import TunnelKitOpenVPNManager

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
        let bundleIdentifier = "com.example.Provider"
        let appGroup = "group.com.algoritmico.TunnelKit"

        let hostname = "example.com"
        let port: UInt16 = 1234
        let serverAddress = "\(hostname):\(port)"
        let credentials = OpenVPN.Credentials("foo", "bar")

        var builder = OpenVPN.ConfigurationBuilder()
        builder.ca = OpenVPN.CryptoContainer(pem: "abcdef")
        builder.cipher = .aes128cbc
        builder.digest = .sha256
        builder.remotes = [.init(hostname, .init(.udp, port))]
        builder.mtu = 1230

        var cfg = OpenVPN.ProviderConfiguration("", appGroup: appGroup, configuration: builder.build())
        cfg.username = credentials.username
        let proto: NETunnelProviderProtocol
        do {
            proto = try cfg.asTunnelProtocol(withBundleIdentifier: bundleIdentifier, extra: nil)
        } catch {
            XCTFail(error.localizedDescription)
            return
        }

        XCTAssertEqual(proto.providerBundleIdentifier, bundleIdentifier)
        XCTAssertEqual(proto.serverAddress, serverAddress)
        XCTAssertEqual(proto.username, credentials.username)

        guard let pc = proto.providerConfiguration else {
            return
        }
        print("\(pc)")

        let ovpn = pc["configuration"] as? [String: Any]
        XCTAssertEqual(pc["appGroup"] as? String, appGroup)
        XCTAssertEqual(pc["shouldDebug"] as? Bool, cfg.shouldDebug)
        XCTAssertEqual(ovpn?["cipher"] as? String, cfg.configuration.cipher?.rawValue)
        XCTAssertEqual(ovpn?["digest"] as? String, cfg.configuration.digest?.rawValue)
        XCTAssertEqual(ovpn?["ca"] as? String, cfg.configuration.ca?.pem)
        XCTAssertEqual(ovpn?["mtu"] as? Int, cfg.configuration.mtu)
        XCTAssertEqual(ovpn?["renegotiatesAfter"] as? TimeInterval, cfg.configuration.renegotiatesAfter)
    }

    func testDNSResolver() {
        let exp = expectation(description: "DNS")
        DNSResolver.resolve("www.google.com", timeout: 1000, queue: .main) {
            defer {
                exp.fulfill()
            }
            switch $0 {
            case .success(let records):
                print("\(records)")

            case .failure:
                print("Can't resolve")
            }
        }
        waitForExpectations(timeout: 5.0, handler: nil)
    }

    func testDNSAddressConversion() {
        let testStrings = [
            "0.0.0.0",
            "1.2.3.4",
            "111.222.333.444",
            "1.0.3.255",
            "1.2.255.4",
            "1.2.3.0",
            "255.255.255.255"
        ]
        for expString in testStrings {
            guard let number = DNSResolver.ipv4(fromString: expString) else {
                XCTAssertEqual(expString, "111.222.333.444")
                continue
            }
            let string = DNSResolver.string(fromIPv4: number)
            XCTAssertEqual(string, expString)
        }
    }

    func testEndpointCycling() {
        CoreConfiguration.masksPrivateData = false

        var builder = OpenVPN.ConfigurationBuilder()
        let hostname = "italy.privateinternetaccess.com"
        builder.remotes = [
            .init(hostname, .init(.tcp6, 2222)),
            .init(hostname, .init(.udp, 1111)),
            .init(hostname, .init(.udp4, 3333))
        ]
        let strategy = ConnectionStrategy(configuration: builder.build())

        let expected = [
            "italy.privateinternetaccess.com:TCP6:2222",
            "italy.privateinternetaccess.com:UDP:1111",
            "italy.privateinternetaccess.com:UDP4:3333"
        ]
        var i = 0
        while strategy.hasEndpoints() {
            guard let remote = strategy.currentRemote else {
                break
            }
            print("\(i): \(remote)")
            XCTAssertEqual(remote.originalEndpoint.description, expected[i])
            i += 1
            guard strategy.tryNextEndpoint() else {
                break
            }
        }
    }

//    func testEndpointCycling4() {
//        CoreConfiguration.masksPrivateData = false
//
//        var builder = OpenVPN.ConfigurationBuilder()
//        builder.hostname = "italy.privateinternetaccess.com"
//        builder.endpointProtocols = [
//            EndpointProtocol(.tcp4, 2222),
//        ]
//        let strategy = ConnectionStrategy(
//            configuration: builder.build(),
//            resolvedRecords: [
//                DNSRecord(address: "111:bbbb:ffff::eeee", isIPv6: true),
//                DNSRecord(address: "11.22.33.44", isIPv6: false),
//            ]
//        )
//
//        let expected = [
//            "11.22.33.44:TCP4:2222"
//        ]
//        var i = 0
//        while strategy.hasEndpoint() {
//            let endpoint = strategy.currentEndpoint()
//            print("\(endpoint)")
//            XCTAssertEqual(endpoint.description, expected[i])
//            i += 1
//            strategy.tryNextEndpoint()
//        }
//    }
//
//    func testEndpointCycling6() {
//        CoreConfiguration.masksPrivateData = false
//
//        var builder = OpenVPN.ConfigurationBuilder()
//        builder.hostname = "italy.privateinternetaccess.com"
//        builder.endpointProtocols = [
//            EndpointProtocol(.udp6, 2222),
//        ]
//        let strategy = ConnectionStrategy(
//            configuration: builder.build(),
//            resolvedRecords: [
//                DNSRecord(address: "111:bbbb:ffff::eeee", isIPv6: true),
//                DNSRecord(address: "11.22.33.44", isIPv6: false),
//            ]
//        )
//
//        let expected = [
//            "111:bbbb:ffff::eeee:UDP6:2222"
//        ]
//        var i = 0
//        while strategy.hasEndpoint() {
//            let endpoint = strategy.currentEndpoint()
//            print("\(endpoint)")
//            XCTAssertEqual(endpoint.description, expected[i])
//            i += 1
//            strategy.tryNextEndpoint()
//        }
//    }
}
