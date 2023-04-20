//
//  ConfigurationParserTests.swift
//  TunnelKitOpenVPNTests
//
//  Created by Davide De Rosa on 11/10/18.
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

class ConfigurationParserTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    // from lines

    func testCompression() throws {
        XCTAssertNil(try OpenVPN.ConfigurationParser.parsed(fromLines: ["comp-lzo"]).warning)
        XCTAssertNoThrow(try OpenVPN.ConfigurationParser.parsed(fromLines: ["comp-lzo no"]))
        XCTAssertNoThrow(try OpenVPN.ConfigurationParser.parsed(fromLines: ["comp-lzo yes"]))
//        XCTAssertThrowsError(try OpenVPN.ConfigurationParser.parsed(fromLines: ["comp-lzo yes"]))

        XCTAssertNoThrow(try OpenVPN.ConfigurationParser.parsed(fromLines: ["compress"]))
        XCTAssertNoThrow(try OpenVPN.ConfigurationParser.parsed(fromLines: ["compress lzo"]))
    }

    func testKeepAlive() throws {
        let cfg1 = try OpenVPN.ConfigurationParser.parsed(fromLines: ["ping 10", "ping-restart 60"])
        let cfg2 = try OpenVPN.ConfigurationParser.parsed(fromLines: ["keepalive 10 60"])
        let cfg3 = try OpenVPN.ConfigurationParser.parsed(fromLines: ["keepalive 15 600"])
        XCTAssertEqual(cfg1.configuration.keepAliveInterval, cfg2.configuration.keepAliveInterval)
        XCTAssertEqual(cfg1.configuration.keepAliveTimeout, cfg2.configuration.keepAliveTimeout)
        XCTAssertNotEqual(cfg1.configuration.keepAliveInterval, cfg3.configuration.keepAliveInterval)
        XCTAssertNotEqual(cfg1.configuration.keepAliveTimeout, cfg3.configuration.keepAliveTimeout)
    }

    func testDHCPOption() throws {
        let lines = [
            "dhcp-option DNS 8.8.8.8",
            "dhcp-option DNS6 ffff::1",
            "dhcp-option DOMAIN first-domain.net",
            "dhcp-option DOMAIN second-domain.org",
            "dhcp-option DOMAIN-SEARCH fake-main.net",
            "dhcp-option DOMAIN-SEARCH main.net",
            "dhcp-option DOMAIN-SEARCH one.com",
            "dhcp-option DOMAIN-SEARCH two.com",
            "dhcp-option PROXY_HTTP 1.2.3.4 8081",
            "dhcp-option PROXY_HTTPS 7.8.9.10 8082",
            "dhcp-option PROXY_AUTO_CONFIG_URL https://pac/",
            "dhcp-option PROXY_BYPASS   foo.com   bar.org     net.chat"
        ]
        XCTAssertNoThrow(try OpenVPN.ConfigurationParser.parsed(fromLines: lines))

        let parsed = try! OpenVPN.ConfigurationParser.parsed(fromLines: lines).configuration
        XCTAssertEqual(parsed.dnsServers, ["8.8.8.8", "ffff::1"])
        XCTAssertEqual(parsed.dnsDomain, "second-domain.org")
        XCTAssertEqual(parsed.searchDomains, ["fake-main.net", "main.net", "one.com", "two.com"])
        XCTAssertEqual(parsed.httpProxy?.address, "1.2.3.4")
        XCTAssertEqual(parsed.httpProxy?.port, 8081)
        XCTAssertEqual(parsed.httpsProxy?.address, "7.8.9.10")
        XCTAssertEqual(parsed.httpsProxy?.port, 8082)
        XCTAssertEqual(parsed.proxyAutoConfigurationURL?.absoluteString, "https://pac/")
        XCTAssertEqual(parsed.proxyBypassDomains, ["foo.com", "bar.org", "net.chat"])
    }

    func testRedirectGateway() throws {
        var parsed: OpenVPN.Configuration

        parsed = try! OpenVPN.ConfigurationParser.parsed(fromLines: []).configuration
        XCTAssertEqual(parsed.routingPolicies, nil)
        XCTAssertNotEqual(parsed.routingPolicies, [])
        parsed = try! OpenVPN.ConfigurationParser.parsed(fromLines: ["redirect-gateway   ipv4   block-local"]).configuration
        XCTAssertEqual(Set(parsed.routingPolicies!), Set([.IPv4, .blockLocal]))
    }

    func testConnectionBlock() throws {
        let lines = ["<connection>", "</connection>"]
        XCTAssertThrowsError(try OpenVPN.ConfigurationParser.parsed(fromLines: lines))
    }

    // from file

    func testPIA() throws {
        let file = try OpenVPN.ConfigurationParser.parsed(fromURL: url(withName: "pia-hungary"))
        XCTAssertEqual(file.configuration.remotes, [
            .init("hungary.privateinternetaccess.com", .init(.udp, 1198)),
            .init("hungary.privateinternetaccess.com", .init(.tcp, 502))
        ])
        XCTAssertEqual(file.configuration.cipher, .aes128cbc)
        XCTAssertEqual(file.configuration.digest, .sha1)
    }

    func testStripped() throws {
        let lines = try OpenVPN.ConfigurationParser.parsed(fromURL: url(withName: "pia-hungary"), returnsStripped: true).strippedLines!
        let stripped = lines.joined(separator: "\n")
        print(stripped)
    }

    func testEncryptedCertificateKey() throws {
        try privateTestEncryptedCertificateKey(pkcs: "1")
        try privateTestEncryptedCertificateKey(pkcs: "8")
    }

    func testXOR() throws {
        let cfg = try OpenVPN.ConfigurationParser.parsed(fromLines: ["scramble xormask F"])
        XCTAssertNil(cfg.warning)
        XCTAssertEqual(cfg.configuration.xorMethod, OpenVPN.XORMethod.xormask(mask: Data(repeating: Character("F").asciiValue!, count: 1)))

        let cfg2 = try OpenVPN.ConfigurationParser.parsed(fromLines: ["scramble reverse"])
        XCTAssertNil(cfg.warning)
        XCTAssertEqual(cfg2.configuration.xorMethod, OpenVPN.XORMethod.reverse)

        let cfg3 = try OpenVPN.ConfigurationParser.parsed(fromLines: ["scramble xorptrpos"])
        XCTAssertNil(cfg.warning)
        XCTAssertEqual(cfg3.configuration.xorMethod, OpenVPN.XORMethod.xorptrpos)

        let cfg4 = try OpenVPN.ConfigurationParser.parsed(fromLines: ["scramble obfuscate FFFF"])
        XCTAssertNil(cfg.warning)
        XCTAssertEqual(cfg4.configuration.xorMethod, OpenVPN.XORMethod.obfuscate(mask: Data(repeating: Character("F").asciiValue!, count: 4)))
    }

    private func privateTestEncryptedCertificateKey(pkcs: String) throws {
        let cfgURL = url(withName: "tunnelbear.enc.\(pkcs)")
        XCTAssertThrowsError(try OpenVPN.ConfigurationParser.parsed(fromURL: cfgURL))
        XCTAssertNoThrow(try OpenVPN.ConfigurationParser.parsed(fromURL: cfgURL, passphrase: "foobar"))
    }

    private func url(withName name: String) -> URL {
        return Bundle.module.url(forResource: name, withExtension: "ovpn")!
    }

}
