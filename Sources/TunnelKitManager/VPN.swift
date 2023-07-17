//
//  VPN.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 9/6/18.
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

/// Helps controlling a VPN without messing with underlying implementations.
public protocol VPN {
    associatedtype Configuration

    associatedtype Extra

    /**
     Synchronizes with the current VPN state.
     */
    func prepare() async

    /**
     Installs the VPN profile.

     - Parameter tunnelBundleIdentifier: The bundle identifier of the tunnel extension.
     - Parameter configuration: The configuration to install.
     - Parameter extra: Optional extra arguments.
     */
    func install(
        _ tunnelBundleIdentifier: String,
        configuration: Configuration,
        extra: Extra?
    ) async throws

    /**
     Reconnects to the VPN with current configuration.

     - Parameter after: The reconnection delay.
     **/
    func reconnect(
        after: DispatchTimeInterval
    ) async throws

    /**
     Reconnects to the VPN installing a new configuration.

     - Parameter tunnelBundleIdentifier: The bundle identifier of the tunnel extension.
     - Parameter configuration: The configuration to install.
     - Parameter extra: Optional extra arguments.
     - Parameter after: The reconnection delay.
     */
    func reconnect(
        _ tunnelBundleIdentifier: String,
        configuration: Configuration,
        extra: Extra?,
        after: DispatchTimeInterval
    ) async throws

    /**
     Disconnects from the VPN.
     */
    func disconnect() async

    /**
     Uninstalls the VPN profile.
     */
    func uninstall() async
}

extension DispatchTimeInterval {

    /// Returns self in nanoseconds.
    public var nanoseconds: UInt64 {
        switch self {
        case .seconds(let sec):
            return UInt64(sec) * NSEC_PER_SEC

        case .milliseconds(let msec):
            return UInt64(msec) * NSEC_PER_MSEC

        case .microseconds(let usec):
            return UInt64(usec) * NSEC_PER_USEC

        case .nanoseconds(let nsec):
            return UInt64(nsec)

        case .never:
            return 0

        @unknown default:
            return 0
        }
    }
}
