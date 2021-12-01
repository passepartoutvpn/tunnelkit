//
//  WireGuardProvider+Configuration.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 11/21/21.
//  Copyright (c) 2021 Davide De Rosa. All rights reserved.
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
import TunnelKitManager
import TunnelKitWireGuardCore
import WireGuardKit

extension WireGuardProvider {
    public struct Configuration {
        public let innerConfiguration: WireGuard.Configuration

        // required by WireGuardTunnelProvider
        public var tunnelConfiguration: TunnelConfiguration {
            return innerConfiguration.tunnelConfiguration
        }
        
        public init(innerConfiguration: WireGuard.Configuration) {
            self.innerConfiguration = innerConfiguration
        }

        private init(wgQuickConfig: String) throws {
            innerConfiguration = try WireGuard.Configuration(wgQuickConfig: wgQuickConfig)
        }
        
        public func generatedTunnelProtocol(withBundleIdentifier bundleIdentifier: String, appGroup: String, context: String) throws -> NETunnelProviderProtocol {

            let protocolConfiguration = NETunnelProviderProtocol()
            protocolConfiguration.providerBundleIdentifier = bundleIdentifier
            protocolConfiguration.serverAddress = innerConfiguration.endpointRepresentation

            let keychain = Keychain(group: appGroup)
            let wgString = innerConfiguration.asWgQuickConfig()
            protocolConfiguration.passwordReference = try keychain.set(password: wgString, for: "", context: context)
            protocolConfiguration.providerConfiguration = ["AppGroup": appGroup]

            return protocolConfiguration
        }
        
        public static func appGroup(from protocolConfiguration: NETunnelProviderProtocol) throws -> String {
            guard let appGroup = protocolConfiguration.providerConfiguration?["AppGroup"] as? String else {
                throw WireGuardProviderError.savedProtocolConfigurationIsInvalid
            }
            return appGroup
        }

        public static func parsed(from protocolConfiguration: NETunnelProviderProtocol) throws -> Configuration {
            guard let passwordReference = protocolConfiguration.passwordReference,
                  let wgString = try? Keychain.password(forReference: passwordReference) else {

                throw WireGuardProviderError.savedProtocolConfigurationIsInvalid
            }
            return try Configuration(wgQuickConfig: wgString)
        }
    }
}
