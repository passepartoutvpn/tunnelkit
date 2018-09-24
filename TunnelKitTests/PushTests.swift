//
//  PushTests.swift
//  TunnelKitTests
//
//  Created by Davide De Rosa on 8/24/18.
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

import XCTest
@testable import TunnelKit

private extension SessionReply {
    func debug() {
        print("IPv4: \(ipv4?.description ?? "none")")
        print("IPv6: \(ipv6?.description ?? "none")")
        print("DNS: \(dnsServers)")
    }
}

class PushTests: XCTestCase {
    
    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testNet30() {
        let msg = "PUSH_REPLY,redirect-gateway def1,dhcp-option DNS 209.222.18.222,dhcp-option DNS 209.222.18.218,ping 10,comp-lzo no,route 10.5.10.1,topology net30,ifconfig 10.5.10.6 10.5.10.5,auth-token AUkQf/b3nj3L+CH4RJPP0Vuq8/gpntr7uPqzjQhncig="
        let reply = try! SessionProxy.PushReply(message: msg)!
        reply.debug()

        XCTAssertEqual(reply.ipv4?.address, "10.5.10.6")
        XCTAssertEqual(reply.ipv4?.addressMask, "255.255.255.255")
        XCTAssertEqual(reply.ipv4?.defaultGateway, "10.5.10.5")
        XCTAssertEqual(reply.dnsServers, ["209.222.18.222", "209.222.18.218"])
    }
    
    func testSubnet() {
        let msg = "PUSH_REPLY,dhcp-option DNS 8.8.8.8,dhcp-option DNS 4.4.4.4,route-gateway 10.8.0.1,topology subnet,ping 10,ping-restart 120,ifconfig 10.8.0.2 255.255.255.0,peer-id 0"
        let reply = try! SessionProxy.PushReply(message: msg)!
        reply.debug()
        
        XCTAssertEqual(reply.ipv4?.address, "10.8.0.2")
        XCTAssertEqual(reply.ipv4?.addressMask, "255.255.255.0")
        XCTAssertEqual(reply.ipv4?.defaultGateway, "10.8.0.1")
        XCTAssertEqual(reply.dnsServers, ["8.8.8.8", "4.4.4.4"])
    }
    
    func testRoute() {
        let msg = "PUSH_REPLY,dhcp-option DNS 8.8.8.8,dhcp-option DNS 4.4.4.4,route-gateway 10.8.0.1,route 192.168.0.0 255.255.255.0 10.8.0.12,topology subnet,ping 10,ping-restart 120,ifconfig 10.8.0.2 255.255.255.0,peer-id 0"
        let reply = try! SessionProxy.PushReply(message: msg)!
        reply.debug()
        
        let route = reply.ipv4!.routes.first!
        
        XCTAssertEqual(route.destination, "192.168.0.0")
        XCTAssertEqual(route.mask, "255.255.255.0")
        XCTAssertEqual(route.gateway, "10.8.0.12")
    }

    func testIPv6() {
        let msg = "PUSH_REPLY,dhcp-option DNS6 2001:4860:4860::8888,dhcp-option DNS6 2001:4860:4860::8844,tun-ipv6,route-gateway 10.8.0.1,topology subnet,ping 10,ping-restart 120,ifconfig-ipv6 fe80::601:30ff:feb7:ec01/64 fe80::601:30ff:feb7:dc02,ifconfig 10.8.0.2 255.255.255.0,peer-id 0"
        let reply = try! SessionProxy.PushReply(message: msg)!
        reply.debug()
        
        XCTAssertEqual(reply.ipv4?.address, "10.8.0.2")
        XCTAssertEqual(reply.ipv4?.addressMask, "255.255.255.0")
        XCTAssertEqual(reply.ipv4?.defaultGateway, "10.8.0.1")
        XCTAssertEqual(reply.ipv6?.address, "fe80::601:30ff:feb7:ec01")
        XCTAssertEqual(reply.ipv6?.addressPrefixLength, 64)
        XCTAssertEqual(reply.ipv6?.defaultGateway, "fe80::601:30ff:feb7:dc02")
        XCTAssertEqual(reply.dnsServers, ["2001:4860:4860::8888", "2001:4860:4860::8844"])
    }
    
    func testCompressionFraming() {
        let msg = "PUSH_REPLY,dhcp-option DNS 8.8.8.8,dhcp-option DNS 4.4.4.4,comp-lzo no,route 10.8.0.1,topology net30,ping 10,ping-restart 120,ifconfig 10.8.0.6 10.8.0.5,peer-id 0,cipher AES-256-CBC"
        let reply = try! SessionProxy.PushReply(message: msg)!
        reply.debug()
        
        XCTAssertEqual(reply.compressionFraming, .compLZO)
    }
    
    func testNCP() {
        let msg = "PUSH_REPLY,dhcp-option DNS 8.8.8.8,dhcp-option DNS 4.4.4.4,comp-lzo no,route 10.8.0.1,topology net30,ping 10,ping-restart 120,ifconfig 10.8.0.6 10.8.0.5,peer-id 0,cipher AES-256-GCM"
        let reply = try! SessionProxy.PushReply(message: msg)!
        reply.debug()

        XCTAssertEqual(reply.cipher, .aes256gcm)
    }

    func testNCPTrailing() {
        let msg = "PUSH_REPLY,dhcp-option DNS 8.8.8.8,dhcp-option DNS 4.4.4.4,comp-lzo no,route 10.8.0.1,topology net30,ping 10,ping-restart 120,ifconfig 10.8.0.18 10.8.0.17,peer-id 3,cipher AES-256-GCM,auth-token"
        let reply = try! SessionProxy.PushReply(message: msg)!
        reply.debug()
        
        XCTAssertEqual(reply.cipher, .aes256gcm)
    }
    
    func testPing() {
        let msg = "PUSH_REPLY,route 192.168.1.0 255.255.255.0,route 10.0.2.0 255.255.255.0,dhcp-option DNS 192.168.1.99,dhcp-option DNS 176.103.130.130,route 10.0.2.1,topology net30,ping 10,ping-restart 60,ifconfig 10.0.2.14 10.0.2.13"
        let reply = try! SessionProxy.PushReply(message: msg)!
        reply.debug()
        
        XCTAssertEqual(reply.ping, 10)
    }
}
