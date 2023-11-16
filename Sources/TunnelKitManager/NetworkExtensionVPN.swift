//
//  NetworkExtensionVPN.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 6/15/18.
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
import SwiftyBeaver

private let log = SwiftyBeaver.self

/// `VPN` based on the NetworkExtension framework.
public class NetworkExtensionVPN: VPN {

    /**
     Initializes a provider.
     */
    public init() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(vpnDidUpdate(_:)), name: .NEVPNStatusDidChange, object: nil)
        nc.addObserver(self, selector: #selector(vpnDidReinstall(_:)), name: .NEVPNConfigurationChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Public

    public func prepare() async {
        _ = try? await NETunnelProviderManager.loadAllFromPreferences()
    }

    public func install(
        _ tunnelBundleIdentifier: String,
        configuration: NetworkExtensionConfiguration,
        extra: NetworkExtensionExtra?
    ) async throws {
        _ = try await installReturningManager(
            tunnelBundleIdentifier,
            configuration: configuration,
            extra: extra
        )
    }

    public func reconnect(after: DispatchTimeInterval) async throws {
        let managers = try await lookupAll()
        guard let manager = managers.first else {
            return
        }
        if manager.connection.status != .disconnected {
            manager.connection.stopVPNTunnel()
            try await Task.sleep(nanoseconds: after.nanoseconds)
        }
        try manager.connection.startVPNTunnel()
    }

    public func reconnect(
        _ tunnelBundleIdentifier: String,
        configuration: NetworkExtensionConfiguration,
        extra: NetworkExtensionExtra?,
        after: DispatchTimeInterval
    ) async throws {
        do {
            let manager = try await installReturningManager(
                tunnelBundleIdentifier,
                configuration: configuration,
                extra: extra
            )
            if manager.connection.status != .disconnected {
                manager.connection.stopVPNTunnel()
                try await Task.sleep(nanoseconds: after.nanoseconds)
            }
            try manager.connection.startVPNTunnel()
        } catch {
            notifyInstallError(error)
            throw error
        }
    }

    public func disconnect() async {
        guard let managers = try? await lookupAll() else {
            return
        }
        guard !managers.isEmpty else {
            return
        }
        for m in managers {
            m.connection.stopVPNTunnel()
            m.isOnDemandEnabled = false
            m.isEnabled = false
            try? await m.saveToPreferences()
        }
    }

    public func uninstall() async {
        guard let managers = try? await lookupAll() else {
            return
        }
        guard !managers.isEmpty else {
            return
        }
        for m in managers {
            m.connection.stopVPNTunnel()
            try? await m.removeFromPreferences()
        }
    }

    // MARK: Helpers

    @discardableResult
    private func installReturningManager(
        _ tunnelBundleIdentifier: String,
        configuration: NetworkExtensionConfiguration,
        extra: NetworkExtensionExtra?
    ) async throws -> NETunnelProviderManager {
        let proto = try configuration.asTunnelProtocol(
            withBundleIdentifier: tunnelBundleIdentifier,
            extra: extra
        )
        let managers = try await lookupAll()

        // install (new or existing) then callback
        let targetManager = managers.first {
            $0.isTunnel(withIdentifier: tunnelBundleIdentifier)
        } ?? NETunnelProviderManager()

        _ = try await install(
            targetManager,
            title: configuration.title,
            protocolConfiguration: proto,
            onDemandRules: extra?.onDemandRules ?? []
        )

        // remove others afterwards (to avoid permission request)
        await retainManagers(managers) {
            $0.isTunnel(withIdentifier: tunnelBundleIdentifier)
        }

        return targetManager
    }

    @discardableResult
    private func install(
        _ manager: NETunnelProviderManager,
        title: String,
        protocolConfiguration: NETunnelProviderProtocol,
        onDemandRules: [NEOnDemandRule]
    ) async throws -> NETunnelProviderManager {
        manager.localizedDescription = title
        manager.protocolConfiguration = protocolConfiguration

        if !onDemandRules.isEmpty {
            manager.onDemandRules = onDemandRules
            manager.isOnDemandEnabled = true
        } else {
            manager.isOnDemandEnabled = false
        }

        manager.isEnabled = true
        do {
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            notifyReinstall(manager)
            return manager
        } catch {
            manager.isOnDemandEnabled = false
            manager.isEnabled = false
            notifyInstallError(error)
            throw error
        }
    }

    private func retainManagers(_ managers: [NETunnelProviderManager], isIncluded: (NETunnelProviderManager) -> Bool) async {
        let others = managers.filter {
            !isIncluded($0)
        }
        guard !others.isEmpty else {
            return
        }
        for o in others {
            try? await o.removeFromPreferences()
        }
    }

    private func lookupAll() async throws -> [NETunnelProviderManager] {
        try await NETunnelProviderManager.loadAllFromPreferences()
    }

    // MARK: Notifications

    @objc private func vpnDidUpdate(_ notification: Notification) {
        guard let connection = notification.object as? NETunnelProviderSession else {
            return
        }
        notifyStatus(connection)
    }

    @objc private func vpnDidReinstall(_ notification: Notification) {
        guard let manager = notification.object as? NETunnelProviderManager else {
            return
        }
        notifyReinstall(manager)
    }

    private func notifyReinstall(_ manager: NETunnelProviderManager) {
        let bundleId = manager.tunnelBundleIdentifier
        log.debug("VPN did reinstall (\(bundleId ?? "?")): isEnabled=\(manager.isEnabled)")

        var notification = Notification(name: VPNNotification.didReinstall)
        notification.vpnBundleIdentifier = bundleId
        notification.vpnIsEnabled = manager.isEnabled
        NotificationCenter.default.post(notification)
    }

    private func notifyStatus(_ connection: NETunnelProviderSession) {
        guard let _ = connection.manager.localizedDescription else {
            log.verbose("Ignoring VPN notification from bogus manager")
            return
        }
        let bundleId = connection.manager.tunnelBundleIdentifier
        log.debug("VPN status did change (\(bundleId ?? "?")): isEnabled=\(connection.manager.isEnabled), status=\(connection.status.rawValue)")
        var notification = Notification(name: VPNNotification.didChangeStatus)
        notification.vpnBundleIdentifier = bundleId
        notification.vpnIsEnabled = connection.manager.isEnabled
        notification.vpnStatus = connection.status.wrappedStatus
        notification.connectionDate = connection.connectedDate
        NotificationCenter.default.post(notification)
    }

    private func notifyInstallError(_ error: Error) {
        log.error("VPN installation failed: \(error))")

        var notification = Notification(name: VPNNotification.didFail)
        notification.vpnError = error
        notification.vpnIsEnabled = false
        NotificationCenter.default.post(notification)
    }
}

private extension NEVPNManager {
    var tunnelBundleIdentifier: String? {
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol else {
            return nil
        }
        return proto.providerBundleIdentifier
    }

    func isTunnel(withIdentifier bundleIdentifier: String) -> Bool {
        return tunnelBundleIdentifier == bundleIdentifier
    }
}

private extension NEVPNStatus {
    var wrappedStatus: VPNStatus {
        switch self {
        case .connected:
            return .connected

        case .connecting, .reasserting:
            return .connecting

        case .disconnecting:
            return .disconnecting

        case .disconnected, .invalid:
            return .disconnected

        @unknown default:
            return .disconnected
        }
    }
}
