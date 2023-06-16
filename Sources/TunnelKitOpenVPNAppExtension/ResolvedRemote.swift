//
//  ResolvedRemote.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 3/3/22.
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

import Foundation
import TunnelKitCore
import SwiftyBeaver

private let log = SwiftyBeaver.self

class ResolvedRemote: CustomStringConvertible {
    let originalEndpoint: Endpoint

    private(set) var isResolved: Bool

    private(set) var resolvedEndpoints: [Endpoint]

    private var currentEndpointIndex: Int

    var currentEndpoint: Endpoint? {
        guard currentEndpointIndex < resolvedEndpoints.count else {
            return nil
        }
        return resolvedEndpoints[currentEndpointIndex]
    }

    init(_ originalEndpoint: Endpoint) {
        self.originalEndpoint = originalEndpoint
        isResolved = false
        resolvedEndpoints = []
        currentEndpointIndex = 0
    }

    func nextEndpoint() -> Bool {
        currentEndpointIndex += 1
        return currentEndpointIndex < resolvedEndpoints.count
    }

    func resolve(timeout: Int, queue: DispatchQueue, completionHandler: @escaping () -> Void) {
        DNSResolver.resolve(originalEndpoint.address, timeout: timeout, queue: queue) { [weak self] in
            self?.handleResult($0)
            completionHandler()
        }
    }

    private func handleResult(_ result: Result<[DNSRecord], Error>) {
        switch result {
        case .success(let records):
            log.debug("DNS resolved addresses: \(records.map { $0.address }.maskedDescription)")
            isResolved = true
            resolvedEndpoints = unrolledEndpoints(records: records)

        case .failure:
            log.error("DNS resolution failed!")
            isResolved = false
            resolvedEndpoints = []
        }
    }

    private func unrolledEndpoints(records: [DNSRecord]) -> [Endpoint] {
        let endpoints = records.filter {
            $0.isCompatible(withProtocol: originalEndpoint.proto)
        }.map {
            Endpoint($0.address, originalEndpoint.proto)
        }
        log.debug("Unrolled endpoints: \(endpoints.maskedDescription)")
        return endpoints
    }

    // MARK: CustomStringConvertible

    var description: String {
        "{\(originalEndpoint.maskedDescription), resolved: \(resolvedEndpoints.maskedDescription)}"
    }
}

private extension DNSRecord {
    func isCompatible(withProtocol proto: EndpointProtocol) -> Bool {
        if isIPv6 {
            return proto.socketType != .udp4 && proto.socketType != .tcp4
        } else {
            return proto.socketType != .udp6 && proto.socketType != .tcp6
        }
    }
}
