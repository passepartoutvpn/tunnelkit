//
//  MockVPN.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 6/15/18.
//  Copyright (c) 2022 Davide De Rosa. All rights reserved.
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

/// Simulates a VPN provider.
public class MockVPN: VPN {
    private var tunnelBundleIdentifier: String?
    
    private var currentIsEnabled = false
    
    public init() {
    }
    
    // MARK: VPN
    
    public func prepare() {
    }
    
    public func install(
        _ tunnelBundleIdentifier: String,
        configuration: NetworkExtensionConfiguration,
        extra: NetworkExtensionExtra?
    ) {
        self.tunnelBundleIdentifier = tunnelBundleIdentifier
        notifyReinstall(true)
        notifyStatus(.disconnected)
    }
    
    public func reconnect(after: DispatchTimeInterval) async throws {
        notifyStatus(.connected)
    }
    
    public func reconnect(
        _ tunnelBundleIdentifier: String,
        configuration: NetworkExtensionConfiguration,
        extra: NetworkExtensionExtra?,
        after: DispatchTimeInterval
    ) async throws {
        self.tunnelBundleIdentifier = tunnelBundleIdentifier
        notifyReinstall(true)
        notifyStatus(.connected)
    }
    
    public func disconnect() async {
        notifyReinstall(false)
        notifyStatus(.disconnected)
    }
    
    public func uninstall() async {
        notifyReinstall(false)
    }
    
    // MARK: Helpers
    
    private func notifyReinstall(_ isEnabled: Bool) {
        currentIsEnabled = isEnabled
        
        var notification = Notification(name: VPNNotification.didReinstall)
        notification.vpnBundleIdentifier = tunnelBundleIdentifier
        notification.vpnIsEnabled = isEnabled
        NotificationCenter.default.post(notification)
    }
    
    private func notifyStatus(_ status: VPNStatus) {
        var notification = Notification(name: VPNNotification.didChangeStatus)
        notification.vpnBundleIdentifier = tunnelBundleIdentifier
        notification.vpnIsEnabled = currentIsEnabled
        notification.vpnStatus = status
        NotificationCenter.default.post(notification)
    }
}
