//
//  WireGuardViewController.swift
//  Demo
//
//  Created by Davide De Rosa on 11/22/21.
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
import TunnelKitManager
import TunnelKitWireGuard

private let appGroup = "DTDYD63ZX9.group.com.algoritmico.TunnelKit.Demo"

private let tunnelIdentifier = "com.algoritmico.macos.TunnelKit.Demo.WireGuard.Tunnel"

class WireGuardViewController: NSViewController {
    @IBOutlet var textClientPrivateKey: NSTextField!

    @IBOutlet var textAddress: NSTextField!

    @IBOutlet var textServerPublicKey: NSTextField!

    @IBOutlet var textServerAddress: NSTextField!

    @IBOutlet var textServerPort: NSTextField!

    @IBOutlet var buttonConnection: NSButton!

    private let vpn = NetworkExtensionVPN()

    private var vpnStatus: VPNStatus = .disconnected

    override func viewDidLoad() {
        super.viewDidLoad()

        textClientPrivateKey.placeholderString = "client private key"
        textAddress.placeholderString = "client address"
        textServerPublicKey.placeholderString = "server public key"
        textServerAddress.placeholderString = "server address"
        textServerPort.placeholderString = "server port"

        textAddress.stringValue = "192.168.30.2/32"

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
        let clientPrivateKey = textClientPrivateKey.stringValue
        let clientAddress = textAddress.stringValue
        let serverPublicKey = textServerPublicKey.stringValue
        let serverAddress = textServerAddress.stringValue
        let serverPort = textServerPort.stringValue

        guard let cfg = WireGuard.DemoConfiguration.make(params: .init(
            title: "TunnelKit.WireGuard",
            appGroup: appGroup,
            clientPrivateKey: clientPrivateKey,
            clientAddress: clientAddress,
            serverPublicKey: serverPublicKey,
            serverAddress: serverAddress,
            serverPort: serverPort
        )) else {
            print("Configuration incomplete")
            return
        }

        Task {
            try await vpn.reconnect(
                tunnelIdentifier,
                configuration: cfg,
                extra: nil,
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
}
