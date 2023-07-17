//
//  OpenVPNViewController.swift
//  Demo
//
//  Created by Davide De Rosa on 10/15/17.
//  Copyright (c) 2023 Davide De Rosa. All rights reserved.
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

import Cocoa
import TunnelKitCore
import TunnelKitManager
import TunnelKitOpenVPN

private let appGroup = "DTDYD63ZX9.group.com.algoritmico.TunnelKit.Demo"

private let tunnelIdentifier = "com.algoritmico.macos.TunnelKit.Demo.OpenVPN.Tunnel"

class OpenVPNViewController: NSViewController {
    @IBOutlet var textUsername: NSTextField!

    @IBOutlet var textPassword: NSTextField!

    @IBOutlet var textServer: NSTextField!

    @IBOutlet var textDomain: NSTextField!

    @IBOutlet var textPort: NSTextField!

    @IBOutlet var buttonConnection: NSButton!

    private let vpn = NetworkExtensionVPN()

    private var vpnStatus: VPNStatus = .disconnected

    private let keychain = Keychain(group: appGroup)

    private var cfg: OpenVPN.ProviderConfiguration?

    override func viewDidLoad() {
        super.viewDidLoad()

        textServer.stringValue = "nl-free-50"
        textDomain.stringValue = "protonvpn.net"
        textPort.stringValue = "80"
        textUsername.stringValue = ""
        textPassword.stringValue = ""

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(VPNStatusDidChange(notification:)),
            name: VPNNotification.didChangeStatus,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(VPNDidFail(notification:)),
            name: VPNNotification.didFail,
            object: nil
        )

        Task {
            await vpn.prepare()
        }

//        testFetchRef()
    }

    @IBAction func connectionClicked(_ sender: Any) {
        switch vpnStatus {
        case .disconnected:
            connect()

        case .connected, .connecting, .disconnecting:
            disconnect()
        }
    }

    func connect() {
        let server = textServer.stringValue
        let domain = textDomain.stringValue
        let hostname = ((domain == "") ? server : [server, domain].joined(separator: "."))
        let port = UInt16(textPort.stringValue)!

        let credentials = OpenVPN.Credentials(textUsername.stringValue, textPassword.stringValue)
        cfg = OpenVPN.DemoConfiguration.make(params: .init(
            title: "TunnelKit.OpenVPN",
            appGroup: appGroup,
            hostname: hostname,
            port: port,
            socketType: .udp
        ))
        cfg?.username = credentials.username

        let passwordReference: Data
        do {
            passwordReference = try keychain.set(password: credentials.password, for: credentials.username, context: tunnelIdentifier)
        } catch {
            print("Keychain failure: \(error)")
            return
        }

        Task {
            var extra = NetworkExtensionExtra()
            extra.passwordReference = passwordReference
            try await vpn.reconnect(
                tunnelIdentifier,
                configuration: cfg!,
                extra: extra,
                after: .seconds(2)
            )
        }
    }

    func disconnect() {
        Task {
            await vpn.disconnect()
        }
    }

    func updateButton() {
        switch vpnStatus {
        case .connected, .connecting:
            buttonConnection.title = "Disconnect"

        case .disconnected:
            buttonConnection.title = "Connect"

        case .disconnecting:
            buttonConnection.title = "Disconnecting"
        }
    }

    @objc private func VPNStatusDidChange(notification: Notification) {
        vpnStatus = notification.vpnStatus
        print("VPNStatusDidChange: \(vpnStatus)")
        updateButton()
    }

    @objc private func VPNDidFail(notification: Notification) {
        print("VPNStatusDidFail: \(notification.vpnError.localizedDescription)")
    }

//    private func testFetchRef() {
//        let keychain = Keychain(group: appGroup)
//        let username = "foo"
//        let password = "bar"
//
//        guard let ref = try? keychain.set(password: password, for: username, context: tunnelIdentifier) else {
//            print("Couldn't set password")
//            return
//        }
//        guard let fetchedPassword = try? Keychain.password(forReference: ref) else {
//            print("Couldn't fetch password")
//            return
//        }
//
//        print("\(username) -> \(password)")
//        print("\(username) -> \(fetchedPassword)")
//    }
}
