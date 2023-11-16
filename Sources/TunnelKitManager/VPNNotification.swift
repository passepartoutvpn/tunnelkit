//
//  VPNNotification.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 6/12/18.
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

/// VPN notifications.
public struct VPNNotification {

    /// The VPN did reinstall.
    public static let didReinstall = Notification.Name("VPNDidReinstall")

    /// The VPN did change its status.
    public static let didChangeStatus = Notification.Name("VPNDidChangeStatus")

    /// The VPN triggered some error.
    public static let didFail = Notification.Name("VPNDidFail")
}

extension Notification {

    /// The VPN bundle identifier.
    public var vpnBundleIdentifier: String? {
        get {
            guard let vpnBundleIdentifier = userInfo?["BundleIdentifier"] as? String else {
                fatalError("Notification has no vpnBundleIdentifier")
            }
            return vpnBundleIdentifier
        }
        set {
            var newInfo = userInfo ?? [:]
            newInfo["BundleIdentifier"] = newValue
            userInfo = newInfo
        }
    }

    /// The current VPN enabled state.
    public var vpnIsEnabled: Bool {
        get {
            guard let vpnIsEnabled = userInfo?["IsEnabled"] as? Bool else {
                fatalError("Notification has no vpnIsEnabled")
            }
            return vpnIsEnabled
        }
        set {
            var newInfo = userInfo ?? [:]
            newInfo["IsEnabled"] = newValue
            userInfo = newInfo
        }
    }

    /// The current VPN status.
    public var vpnStatus: VPNStatus {
        get {
            guard let vpnStatus = userInfo?["Status"] as? VPNStatus else {
                fatalError("Notification has no vpnStatus")
            }
            return vpnStatus
        }
        set {
            var newInfo = userInfo ?? [:]
            newInfo["Status"] = newValue
            userInfo = newInfo
        }
    }

    /// The triggered VPN error.
    public var vpnError: Error {
        get {
            guard let vpnError = userInfo?["Error"] as? Error else {
                fatalError("Notification has no vpnError")
            }
            return vpnError
        }
        set {
            var newInfo = userInfo ?? [:]
            newInfo["Error"] = newValue
            userInfo = newInfo
        }
    }

    /// The current VPN connection date.
    public var connectionDate: Date? {
        get {
            guard let date = userInfo?["ConnectionDate"] as? Date else {
                fatalError("Notification has no connectionDate")
            }
            return date
        }
        set {
            var newInfo = userInfo ?? [:]
            newInfo["ConnectionDate"] = newValue
            userInfo = newInfo
        }
    }
}
