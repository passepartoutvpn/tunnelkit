//
//  ViewController.swift
//  BasicTunnel-macOS
//
//  Created by Davide De Rosa on 10/15/17.
//  Copyright © 2018 Davide De Rosa. All rights reserved.
//

import Cocoa
import NetworkExtension
import TunnelKit

extension ViewController {
    private static let appGroup = "group.com.algoritmico.macos.demo.BasicTunnel"
    
    private static let bundleIdentifier = "com.algoritmico.macos.demo.BasicTunnel.BasicTunnelExtension"
    
    private func makeProtocol() -> NETunnelProviderProtocol {
        let server = textServer.stringValue
        let domain = textDomain.stringValue
        
        let hostname = ((domain == "") ? server : [server, domain].joined(separator: "."))
        let port = UInt16(textPort.stringValue)!
        let username = textUsername.stringValue
        let password = textPassword.stringValue

        let endpoint = TunnelKitProvider.AuthenticatedEndpoint(
            hostname: hostname,
            username: username,
            password: password
        )

        var builder = TunnelKitProvider.ConfigurationBuilder()
//        let socketType: TunnelKitProvider.SocketType = isTCP ? .tcp : .udp
        let socketType: TunnelKitProvider.SocketType = .udp
        builder.endpointProtocols = [TunnelKitProvider.EndpointProtocol(socketType, port)]
        builder.cipher = .aes128cbc
        builder.digest = .sha1
        builder.mtu = 1350
        builder.compressionFraming = .compLZO
        builder.renegotiatesAfterSeconds = nil
        builder.shouldDebug = true
        builder.debugLogKey = "Log"
        
        let configuration = builder.build()
        return try! configuration.generatedTunnelProtocol(
            withBundleIdentifier: ViewController.bundleIdentifier,
            appGroup: ViewController.appGroup,
            endpoint: endpoint
        )
    }
}

class ViewController: NSViewController {
    @IBOutlet var textUsername: NSTextField!
    
    @IBOutlet var textPassword: NSTextField!
    
    @IBOutlet var textServer: NSTextField!
    
    @IBOutlet var textDomain: NSTextField!
    
    @IBOutlet var textPort: NSTextField!
    
    @IBOutlet var buttonConnection: NSButton!
    
    var currentManager: NETunnelProviderManager?
    
    var status = NEVPNStatus.invalid
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        textServer.stringValue = "germany"
        textDomain.stringValue = "privateinternetaccess.com"
        textPort.stringValue = "1198"
        textUsername.stringValue = "myusername"
        textPassword.stringValue = "mypassword"
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(VPNStatusDidChange(notification:)),
            name: .NEVPNStatusDidChange,
            object: nil
        )
        
        reloadCurrentManager(nil)
        
        //
        
        testFetchRef()
    }
    
    @IBAction func connectionClicked(_ sender: Any) {
        let block = {
            switch (self.status) {
            case .invalid, .disconnected:
                self.connect()
                
            case .connected, .connecting:
                self.disconnect()
                
            default:
                break
            }
        }
        
        if (status == .invalid) {
            reloadCurrentManager({ (error) in
                block()
            })
        }
        else {
            block()
        }
    }
    
    func connect() {
        configureVPN({ (manager) in
            return self.makeProtocol()
        }, completionHandler: { (error) in
            if let error = error {
                print("configure error: \(error)")
                return
            }
            let session = self.currentManager?.connection as! NETunnelProviderSession
            do {
                try session.startTunnel()
            } catch let e {
                print("error starting tunnel: \(e)")
            }
        })
    }
    
    func disconnect() {
        configureVPN({ (manager) in
            return nil
        }, completionHandler: { (error) in
            self.currentManager?.connection.stopVPNTunnel()
        })
    }
    
    func configureVPN(_ configure: @escaping (NETunnelProviderManager) -> NETunnelProviderProtocol?, completionHandler: @escaping (Error?) -> Void) {
        reloadCurrentManager { (error) in
            if let error = error {
                print("error reloading preferences: \(error)")
                completionHandler(error)
                return
            }
            
            let manager = self.currentManager!
            if let protocolConfiguration = configure(manager) {
                manager.protocolConfiguration = protocolConfiguration
            }
            manager.isEnabled = true
            
            manager.saveToPreferences { (error) in
                if let error = error {
                    print("error saving preferences: \(error)")
                    completionHandler(error)
                    return
                }
                print("saved preferences")
                self.reloadCurrentManager(completionHandler)
            }
        }
    }
    
    func reloadCurrentManager(_ completionHandler: ((Error?) -> Void)?) {
        NETunnelProviderManager.loadAllFromPreferences { (managers, error) in
            if let error = error {
                completionHandler?(error)
                return
            }
            
            var manager: NETunnelProviderManager?
            
            for m in managers! {
                if let p = m.protocolConfiguration as? NETunnelProviderProtocol {
                    if (p.providerBundleIdentifier == ViewController.bundleIdentifier) {
                        manager = m
                        break
                    }
                }
            }
            
            if (manager == nil) {
                manager = NETunnelProviderManager()
            }
            
            self.currentManager = manager
            self.status = manager!.connection.status
            self.updateButton()
            completionHandler?(nil)
        }
    }
    
    func updateButton() {
        switch status {
        case .connected, .connecting:
            buttonConnection.title = "Disconnect"
            
        case .disconnected:
            buttonConnection.title = "Connect"
            
        case .disconnecting:
            buttonConnection.title = "Disconnecting"
            
        default:
            break
        }
    }
    
    @objc private func VPNStatusDidChange(notification: NSNotification) {
        guard let status = currentManager?.connection.status else {
            print("VPNStatusDidChange")
            return
        }
        print("VPNStatusDidChange: \(status.rawValue)")
        self.status = status
        updateButton()
    }
    
    private func testFetchRef() {
//        let keychain = Keychain(group: ViewController.APP_GROUP)
//        let username = "foo"
//        let password = "bar"
//
//        guard let _ = try? keychain.set(password: password, for: username) else {
//            print("Couldn't set password")
//            return
//        }
//        guard let passwordReference = try? keychain.passwordReference(for: username) else {
//            print("Couldn't get password reference")
//            return
//        }
//        guard let fetchedPassword = try? Keychain.password(for: username, reference: passwordReference) else {
//            print("Couldn't fetch password")
//            return
//        }
//
//        print("\(username) -> \(password)")
//        print("\(username) -> \(fetchedPassword)")
    }
}

