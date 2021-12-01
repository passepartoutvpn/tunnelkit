//
//  WireGuardViewController.swift
//  Demo
//
//  Created by Davide De Rosa on 11/22/21.
//  Copyright (c) 2021 Davide De Rosa. All rights reserved.
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
import NetworkExtension

private let appGroup = "DTDYD63ZX9.group.com.algoritmico.TunnelKit.Demo"

private let tunnelIdentifier = "com.algoritmico.macos.TunnelKit.Demo.WireGuard.Tunnel"

class WireGuardViewController: NSViewController {
    @IBOutlet var textClientPrivateKey: NSTextField!
    
    @IBOutlet var textAddress: NSTextField!
    
    @IBOutlet var textServerPublicKey: NSTextField!
    
    @IBOutlet var textServerAddress: NSTextField!
    
    @IBOutlet var textServerPort: NSTextField!
    
    @IBOutlet var buttonConnection: NSButton!
    
    private let vpn = WireGuardProvider(bundleIdentifier: tunnelIdentifier)

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
            name: VPN.didChangeStatus,
            object: nil
        )
        
        vpn.prepare(completionHandler: nil)
    }

    @IBAction func connectionClicked(_ sender: Any) {
        switch vpn.status {
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

        guard let cfg = WireGuard.DemoConfiguration.make(
            clientPrivateKey: clientPrivateKey,
            clientAddress: clientAddress,
            serverPublicKey: serverPublicKey,
            serverAddress: serverAddress,
            serverPort: serverPort
        ) else {
            print("Configuration incomplete")
            return
        }
        let proto = try! cfg.generatedTunnelProtocol(
            withBundleIdentifier: tunnelIdentifier,
            appGroup: appGroup,
            context: tunnelIdentifier
        )

        let neCfg = NetworkExtensionVPNConfiguration(title: "TunnelKit.WireGuard", protocolConfiguration: proto, onDemandRules: [])
        vpn.reconnect(configuration: neCfg) { (error) in
            if let error = error {
                print("configure error: \(error)")
                return
            }
        }
    }
    
    func disconnect() {
        vpn.disconnect(completionHandler: nil)
    }

    func updateButton() {
        switch vpn.status {
        case .connected, .connecting:
            buttonConnection.title = "Disconnect"
            
        case .disconnected:
            buttonConnection.title = "Connect"
            
        case .disconnecting:
            buttonConnection.title = "Disconnecting"
        }
    }
    
    @objc private func VPNStatusDidChange(notification: NSNotification) {
        print("VPNStatusDidChange: \(vpn.status)")
        updateButton()
    }
}
