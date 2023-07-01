//
//  OpenVPN+ProviderConfiguration.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 3/6/22.
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
import TunnelKitManager
import TunnelKitCore
import TunnelKitOpenVPNCore
import NetworkExtension
import SwiftyBeaver
import __TunnelKitUtils

private let log = SwiftyBeaver.self

extension OpenVPN {

    /// Specific configuration for OpenVPN.
    public struct ProviderConfiguration: Codable {
        fileprivate enum Keys: String {
            case logPath = "OpenVPN.LogPath"

            case dataCount = "OpenVPN.DataCount"

            case serverConfiguration = "OpenVPN.ServerConfiguration"

            case lastError = "OpenVPN.LastError"
        }

        /// Optional version identifier about the client pushed to server in peer-info as `IV_UI_VER`.
        public var versionIdentifier: String?

        /// The configuration title.
        public let title: String

        /// The access group for shared data.
        public let appGroup: String

        /// The client configuration.
        public let configuration: OpenVPN.Configuration

        /// The optional username.
        public var username: String?

        /// Enables debugging.
        public var shouldDebug = false

        /// Debug log path.
        public var debugLogPath: String?

        /// Optional debug log format (SwiftyBeaver format).
        public var debugLogFormat: String?

        /// Mask private data in debug log (default is `true`).
        public var masksPrivateData = true

        public init(_ title: String, appGroup: String, configuration: OpenVPN.Configuration) {
            self.title = title
            self.appGroup = appGroup
            self.configuration = configuration
        }

        public func print() {
            if let versionIdentifier = versionIdentifier {
                log.info("Tunnel version: \(versionIdentifier)")
            }
            log.info("Debug: \(shouldDebug)")
            log.info("Masks private data: \(masksPrivateData)")
            log.info("Local options:")
            configuration.print(isLocal: true)
        }
    }
}

// MARK: NetworkExtensionConfiguration

extension OpenVPN.ProviderConfiguration: NetworkExtensionConfiguration {

    public func asTunnelProtocol(
        withBundleIdentifier tunnelBundleIdentifier: String,
        extra: NetworkExtensionExtra?
    ) throws -> NETunnelProviderProtocol {
        guard let firstRemote = configuration.remotes?.first else {
            preconditionFailure("No remotes set")
        }

        let protocolConfiguration = NETunnelProviderProtocol()
        protocolConfiguration.providerBundleIdentifier = tunnelBundleIdentifier
        protocolConfiguration.serverAddress = "\(firstRemote.address):\(firstRemote.proto.port)"
        if let username = username {
            protocolConfiguration.username = username
            protocolConfiguration.passwordReference = extra?.passwordReference
        }
        protocolConfiguration.disconnectOnSleep = extra?.disconnectsOnSleep ?? false
        protocolConfiguration.providerConfiguration = try asDictionary()
        protocolConfiguration.includeAllNetworks = extra?.killSwitch ?? false
        return protocolConfiguration
    }
}

// MARK: Shared data

extension OpenVPN.ProviderConfiguration {

    /**
     The most recent (received, sent) count in bytes.
     */
    public var dataCount: DataCount? {
        return defaults?.openVPNDataCount
    }

    /**
     The server configuration pulled by the VPN.
     */
    public var serverConfiguration: OpenVPN.Configuration? {
        return defaults?.openVPNServerConfiguration
    }

    /**
     The last error reported by the tunnel, if any.
     */
    public var lastError: TunnelKitOpenVPNError? {
        return defaults?.openVPNLastError
    }

    /**
     The URL of the latest debug log.
     */
    public var urlForDebugLog: URL? {
        return defaults?.openVPNURLForDebugLog(appGroup: appGroup)
    }

    private var defaults: UserDefaults? {
        return UserDefaults(suiteName: appGroup)
    }
}

extension OpenVPN.ProviderConfiguration {
    public func _appexSetDataCount(_ newValue: DataCount?) {
        defaults?.openVPNDataCount = newValue
    }

    public func _appexSetServerConfiguration(_ newValue: OpenVPN.Configuration?) {
        defaults?.openVPNServerConfiguration = newValue
    }

    public func _appexSetLastError(_ newValue: TunnelKitOpenVPNError?) {
        defaults?.openVPNLastError = newValue
    }

    public var _appexDebugLogURL: URL? {
        guard let path = debugLogPath else {
            return nil
        }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(path)
    }

    public func _appexSetDebugLogPath() {
        defaults?.setValue(debugLogPath, forKey: OpenVPN.ProviderConfiguration.Keys.logPath.rawValue)
    }
}

extension UserDefaults {
    public func openVPNURLForDebugLog(appGroup: String) -> URL? {
        guard let path = string(forKey: OpenVPN.ProviderConfiguration.Keys.logPath.rawValue) else {
            return nil
        }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(path)
    }

    public fileprivate(set) var openVPNDataCount: DataCount? {
        get {
            guard let rawValue = openVPNDataCountArray else {
                return nil
            }
            guard rawValue.count == 2 else {
                return nil
            }
            return DataCount(rawValue[0], rawValue[1])
        }
        set {
            guard let newValue = newValue else {
                openVPNRemoveDataCountArray()
                return
            }
            openVPNDataCountArray = [newValue.received, newValue.sent]
        }
    }

    @objc private var openVPNDataCountArray: [UInt]? {
        get {
            return array(forKey: OpenVPN.ProviderConfiguration.Keys.dataCount.rawValue) as? [UInt]
        }
        set {
            set(newValue, forKey: OpenVPN.ProviderConfiguration.Keys.dataCount.rawValue)
        }
    }

    private func openVPNRemoveDataCountArray() {
        removeObject(forKey: OpenVPN.ProviderConfiguration.Keys.dataCount.rawValue)
    }

    public fileprivate(set) var openVPNServerConfiguration: OpenVPN.Configuration? {
        get {
            guard let raw = data(forKey: OpenVPN.ProviderConfiguration.Keys.serverConfiguration.rawValue) else {
                return nil
            }
            let decoder = JSONDecoder()
            do {
                let cfg = try decoder.decode(OpenVPN.Configuration.self, from: raw)
                return cfg
            } catch {
                log.error("Unable to decode server configuration: \(error)")
                return nil
            }
        }
        set {
            guard let newValue = newValue else {
                return
            }
            let encoder = JSONEncoder()
            do {
                let raw = try encoder.encode(newValue)
                set(raw, forKey: OpenVPN.ProviderConfiguration.Keys.serverConfiguration.rawValue)
            } catch {
                log.error("Unable to encode server configuration: \(error)")
            }
        }
    }

    public fileprivate(set) var openVPNLastError: TunnelKitOpenVPNError? {
        get {
            guard let rawValue = string(forKey: OpenVPN.ProviderConfiguration.Keys.lastError.rawValue) else {
                return nil
            }
            return TunnelKitOpenVPNError(rawValue: rawValue)
        }
        set {
            guard let newValue = newValue else {
                removeObject(forKey: OpenVPN.ProviderConfiguration.Keys.lastError.rawValue)
                return
            }
            set(newValue.rawValue, forKey: OpenVPN.ProviderConfiguration.Keys.lastError.rawValue)
        }
    }
}
