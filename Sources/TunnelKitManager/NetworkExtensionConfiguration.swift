//
//  NetworkExtensionConfiguration.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 9/18/18.
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
import NetworkExtension

/// Extra configuration parameters to attach optionally to a `NetworkExtensionConfiguration`.
public struct NetworkExtensionExtra {

    /// A password reference to the keychain.
    public var passwordReference: Data?

    /// A set of on-demand rules.
    public var onDemandRules: [NEOnDemandRule] = []

    /// Disconnects on sleep if `true`.
    public var disconnectsOnSleep = false

    /// Enables best-effort kill switch.
    public var killSwitch = false

    public init() {
    }
}

/// Configuration object to feed to a `NetworkExtensionProvider`.
public protocol NetworkExtensionConfiguration {

    /// The profile title in device settings.
    var title: String { get }

    /**
     Returns a representation for use with tunnel implementations.
     
     - Parameter bundleIdentifier: The bundle identifier of the tunnel extension.
     - Parameter extra: The optional `Extra` arguments.
     - Returns An object to use with tunnel implementations.
     */
    func asTunnelProtocol(
        withBundleIdentifier bundleIdentifier: String,
        extra: NetworkExtensionExtra?
    ) throws -> NETunnelProviderProtocol
}
