//
//  DNSResolver.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 12/15/17.
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

import Foundation

/// :nodoc:
public class DNSResolver {
    private static let queue = DispatchQueue(label: "DNSResolver")

    public static func resolve(_ hostname: String, timeout: Int, queue: DispatchQueue, completionHandler: @escaping ([String]?, Error?) -> Void) {
        var pendingHandler: (([String]?, Error?) -> Void)? = completionHandler
        let host = CFHostCreateWithName(nil, hostname as CFString).takeRetainedValue()
        DNSResolver.queue.async {
            CFHostStartInfoResolution(host, .addresses, nil)
            guard let handler = pendingHandler else {
                return
            }
            DNSResolver.didResolve(host: host) { (addrs, error) in
                queue.async {
                    handler(addrs, error)
                    pendingHandler = nil
                }
            }
        }
        queue.asyncAfter(deadline: .now() + .milliseconds(timeout)) {
            guard let handler = pendingHandler else {
                return
            }
            CFHostCancelInfoResolution(host, .addresses)
            handler(nil, nil)
            pendingHandler = nil
        }
    }
    
    private static func didResolve(host: CFHost, completionHandler: @escaping ([String]?, Error?) -> Void) {
        var success: DarwinBoolean = false
        guard let rawAddresses = CFHostGetAddressing(host, &success)?.takeUnretainedValue() as Array? else {
            completionHandler(nil, nil)
            return
        }
        
        var ipAddresses: [String] = []
        for case var rawAddress as Data in rawAddresses {
            var ipAddress = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = rawAddress.withUnsafeBytes { (addr: UnsafePointer<sockaddr>) in
                return getnameinfo(
                    addr,
                    socklen_t(rawAddress.count),
                    &ipAddress,
                    socklen_t(ipAddress.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
            }
            guard result == 0 else {
                continue
            }
            ipAddresses.append(String(cString: ipAddress))
        }
        completionHandler(ipAddresses, nil)
    }

    public static func string(fromIPv4 ipv4: UInt32) -> String {
        let a = UInt8(ipv4 & UInt32(0xff))
        let b = UInt8((ipv4 >> 8) & UInt32(0xff))
        let c = UInt8((ipv4 >> 16) & UInt32(0xff))
        let d = UInt8((ipv4 >> 24) & UInt32(0xff))

        return "\(a).\(b).\(c).\(d)"
    }
    
    public static func ipv4(fromString string: String) -> UInt32? {
        let comps = string.components(separatedBy: ".")
        guard comps.count == 4 else {
            return nil
        }
        var ipv4: UInt32 = 0
        var bits: UInt32 = 0
        comps.forEach {
            guard let octet = UInt32($0), octet <= 255 else {
                return
            }
            ipv4 |= octet << bits
            bits += 8
        }
        return ipv4
    }

    private init() {
    }
}
