//
//  WireGuard+ProviderConfiguration.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 11/21/21.
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
import TunnelKitCore
import TunnelKitManager
import TunnelKitWireGuardCore
import WireGuardKit
import SwiftyBeaver
import __TunnelKitUtils

private let log = SwiftyBeaver.self

extension WireGuard {

    /// Specific configuration for WireGuard.
    public struct ProviderConfiguration: Codable {
        fileprivate enum Keys: String {
            case logPath = "WireGuard.LogPath"

            case lastError = "WireGuard.LastError"

            case dataCount = "WireGuard.DataCount"
        }

        public let title: String

        public let appGroup: String

        public let configuration: WireGuard.Configuration

        public var shouldDebug = false

        public var debugLogPath: String?

        public var debugLogFormat: String?

        public init(_ title: String, appGroup: String, configuration: WireGuard.Configuration) {
            self.title = title
            self.appGroup = appGroup
            self.configuration = configuration
        }

        private init(_ title: String, appGroup: String, wgQuickConfig: String) throws {
            self.title = title
            self.appGroup = appGroup
            configuration = try WireGuard.Configuration(wgQuickConfig: wgQuickConfig)
        }
    }
}

// MARK: NetworkExtensionConfiguration

extension WireGuard.ProviderConfiguration: NetworkExtensionConfiguration {

    public func asTunnelProtocol(
        withBundleIdentifier tunnelBundleIdentifier: String,
        extra: NetworkExtensionExtra?
    ) throws -> NETunnelProviderProtocol {
        let protocolConfiguration = NETunnelProviderProtocol()
        protocolConfiguration.providerBundleIdentifier = tunnelBundleIdentifier
        protocolConfiguration.serverAddress = configuration.endpointRepresentation
        protocolConfiguration.passwordReference = extra?.passwordReference
        protocolConfiguration.disconnectOnSleep = extra?.disconnectsOnSleep ?? false
        protocolConfiguration.providerConfiguration = try asDictionary()
        protocolConfiguration.includeAllNetworks = extra?.killSwitch ?? false
        return protocolConfiguration
    }
}

// MARK: Shared data

extension WireGuard.ProviderConfiguration {

    /// The most recent (received, sent) count in bytes.
    public var dataCount: DataCount? {
        return defaults?.wireGuardDataCount
    }

    public var lastError: TunnelKitWireGuardError? {
        return defaults?.wireGuardLastError
    }

    public var urlForDebugLog: URL? {
        return defaults?.wireGuardURLForDebugLog(appGroup: appGroup)
    }

    private var defaults: UserDefaults? {
        return UserDefaults(suiteName: appGroup)
    }

}

extension WireGuard.ProviderConfiguration {
    public func _appexSetDataCount(_ newValue: DataCount?) {
        defaults?.wireGuardDataCount = newValue
    }

    public func _appexSetLastError(_ newValue: TunnelKitWireGuardError?) {
        defaults?.wireGuardLastError = newValue
    }

    public var _appexDebugLogURL: URL? {
        guard let path = debugLogPath else {
            return nil
        }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(path)
    }

    public func _appexSetDebugLogPath() {
        defaults?.setValue(debugLogPath, forKey: WireGuard.ProviderConfiguration.Keys.logPath.rawValue)
    }
}

extension UserDefaults {
    public func wireGuardURLForDebugLog(appGroup: String) -> URL? {
        guard let path = string(forKey: WireGuard.ProviderConfiguration.Keys.logPath.rawValue) else {
            return nil
        }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(path)
    }

    public fileprivate(set) var wireGuardLastError: TunnelKitWireGuardError? {
        get {
            guard let rawValue = string(forKey: WireGuard.ProviderConfiguration.Keys.lastError.rawValue) else {
                return nil
            }
            return TunnelKitWireGuardError(rawValue: rawValue)
        }
        set {
            guard let newValue = newValue else {
                removeObject(forKey: WireGuard.ProviderConfiguration.Keys.lastError.rawValue)
                return
            }
            set(newValue.rawValue, forKey: WireGuard.ProviderConfiguration.Keys.lastError.rawValue)
        }
    }

    public fileprivate(set) var wireGuardDataCount: DataCount? {
        get {
            guard let rawValue = wireGuardDataCountArray else {
                return nil
            }
            guard rawValue.count == 2 else {
                return nil
            }
            return DataCount(rawValue[0], rawValue[1])
        }
        set {
            guard let newValue = newValue else {
                wireGuardRemoveDataCountArray()
                return
            }
            wireGuardDataCountArray = [newValue.received, newValue.sent]
        }
    }

    @objc private var wireGuardDataCountArray: [UInt]? {
        get {
            return array(forKey: WireGuard.ProviderConfiguration.Keys.dataCount.rawValue) as? [UInt]
        }
        set {
            set(newValue, forKey: WireGuard.ProviderConfiguration.Keys.dataCount.rawValue)
        }
    }
    private func wireGuardRemoveDataCountArray() {
        removeObject(forKey: WireGuard.ProviderConfiguration.Keys.dataCount.rawValue)
    }
}
