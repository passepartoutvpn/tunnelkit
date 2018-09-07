//
//  TunnelKitProvider.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 2/1/17.
//  Copyright (c) 2018 Davide De Rosa. All rights reserved.
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
//  This file incorporates work covered by the following copyright and
//  permission notice:
//
//      Copyright (c) 2018-Present Private Internet Access
//
//      Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//      The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//      THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//
//

import NetworkExtension
import SwiftyBeaver

private let log = SwiftyBeaver.self

/**
 Provides an all-in-one `NEPacketTunnelProvider` implementation for use in a
 Packet Tunnel Provider extension both on iOS and macOS.
 */
open class TunnelKitProvider: NEPacketTunnelProvider {
    
    // MARK: Tweaks
    
    /// An optional string describing host app version on tunnel start.
    public var appVersion: String?

    /// The log separator between sessions.
    public var logSeparator = "--- EOF ---"
    
    /// The maximum number of lines in the log.
    public var maxLogLines = 1000
    
    /// The number of milliseconds after which a DNS resolution fails.
    public var dnsTimeout = 3000
    
    /// The number of milliseconds after which the tunnel gives up on a connection attempt.
    public var socketTimeout = 5000
    
    /// The number of milliseconds after which the tunnel is shut down forcibly.
    public var shutdownTimeout = 2000
    
    /// The number of milliseconds after which a reconnection attempt is issued.
    public var reconnectionDelay = 1000
    
    /// The number of link failures after which the tunnel is expected to die.
    public var maxLinkFailures = 3

    // MARK: Constants
    
    private let memoryLog = MemoryDestination()

    private let observer = InterfaceObserver()
    
    private let tunnelQueue = DispatchQueue(label: TunnelKitProvider.description())
    
    private let prngSeedLength = 64
    
    private var cachesURL: URL {
        return URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0])
    }

    private func temporaryURL(forKey key: String) -> URL {
        return cachesURL.appendingPathComponent("\(key).pem")
    }
    
    // MARK: Tunnel configuration

    private var appGroup: String!

    private var cfg: Configuration!
    
    private var strategy: ConnectionStrategy!
    
    private lazy var defaults = UserDefaults(suiteName: appGroup)
    
    // MARK: Internal state

    private var proxy: SessionProxy?
    
    private var socket: GenericSocket?

    private var linkFailures = 0

    private var pendingStartHandler: ((Error?) -> Void)?
    
    private var pendingStopHandler: (() -> Void)?
    
    // MARK: NEPacketTunnelProvider (XPC queue)
    
    /// :nodoc:
    open override func startTunnel(options: [String : NSObject]? = nil, completionHandler: @escaping (Error?) -> Void) {
        let endpoint: AuthenticatedEndpoint
        do {
            guard let tunnelProtocol = protocolConfiguration as? NETunnelProviderProtocol else {
                throw ProviderError.configuration(field: "protocolConfiguration")
            }
            guard let providerConfiguration = tunnelProtocol.providerConfiguration else {
                throw ProviderError.configuration(field: "protocolConfiguration.providerConfiguration")
            }
            try endpoint = AuthenticatedEndpoint(protocolConfiguration: tunnelProtocol)
            try appGroup = Configuration.appGroup(from: providerConfiguration)
            try cfg = Configuration.parsed(from: providerConfiguration)
        } catch let e {
            var message: String?
            if let te = e as? ProviderError {
                switch te {
                case .credentials(let field):
                    message = "Tunnel credentials unavailable: \(field)"
                    
                case .configuration(let field):
                    message = "Tunnel configuration incomplete: \(field)"
                    
                default:
                    break
                }
            }
            NSLog(message ?? "Unexpected error in tunnel configuration: \(e)")
            completionHandler(e)
            return
        }

        strategy = ConnectionStrategy(hostname: endpoint.hostname, configuration: cfg)

        if let defaults = defaults, var existingLog = cfg.existingLog(in: defaults) {
            if let i = existingLog.index(of: logSeparator) {
                existingLog.removeFirst(i + 2)
            }
            
            existingLog.append("")
            existingLog.append(logSeparator)
            existingLog.append("")
            memoryLog.start(with: existingLog)
        }

        configureLogging(
            debug: cfg.shouldDebug,
            customFormat: cfg.debugLogFormat
        )
        
        log.info("Starting tunnel...")
        
        guard SessionProxy.EncryptionBridge.prepareRandomNumberGenerator(seedLength: prngSeedLength) else {
            completionHandler(ProviderError.prngInitialization)
            return
        }
        
        let caPath: String?
        let clientCertificatePath: String?
        let clientKeyPath: String?
        if let ca = cfg.ca {
            do {
                let url = temporaryURL(forKey: Configuration.Keys.ca)
                try ca.write(to: url)
                caPath = url.path
            } catch {
                completionHandler(ProviderError.certificateSerialization)
                return
            }
        } else {
            caPath = nil
        }
        if let clientCertificate = cfg.clientCertificate {
            do {
                let url = temporaryURL(forKey: Configuration.Keys.clientCertificate)
                try clientCertificate.write(to: url)
                clientCertificatePath = url.path
            } catch {
                completionHandler(ProviderError.certificateSerialization)
                return
            }
        } else {
            clientCertificatePath = nil
        }
        if let clientKey = cfg.clientKey {
            do {
                let url = temporaryURL(forKey: Configuration.Keys.clientKey)
                try clientKey.write(to: url)
                clientKeyPath = url.path
            } catch {
                completionHandler(ProviderError.certificateSerialization)
                return
            }
        } else {
            clientKeyPath = nil
        }

        cfg.print(appVersion: appVersion)
        
//        log.info("Temporary CA is stored to: \(caPath)")
        var sessionConfiguration = SessionProxy.ConfigurationBuilder(username: endpoint.username, password: endpoint.password)
        sessionConfiguration.cipher = cfg.cipher
        sessionConfiguration.digest = cfg.digest
        sessionConfiguration.caPath = caPath
        sessionConfiguration.clientCertificatePath = clientCertificatePath
        sessionConfiguration.clientKeyPath = clientKeyPath
        sessionConfiguration.compressionFraming = cfg.compressionFraming
        if let renegotiatesAfterSeconds = cfg.renegotiatesAfterSeconds {
            sessionConfiguration.renegotiatesAfter = Double(renegotiatesAfterSeconds)
        }
        sessionConfiguration.keepAliveInterval = CoreConfiguration.pingInterval

        let proxy: SessionProxy
        do {
            proxy = try SessionProxy(queue: tunnelQueue, configuration: sessionConfiguration.build())
        } catch let e {
            completionHandler(e)
            return
        }
        proxy.delegate = self
        self.proxy = proxy

        logCurrentSSID()

        pendingStartHandler = completionHandler
        tunnelQueue.sync {
            self.connectTunnel()
        }
    }
    
    /// :nodoc:
    open override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        pendingStartHandler = nil
        log.info("Stopping tunnel...")

        guard let proxy = proxy else {
            flushLog()
            completionHandler()
            return
        }

        pendingStopHandler = completionHandler
        tunnelQueue.schedule(after: .milliseconds(shutdownTimeout)) {
            guard let pendingHandler = self.pendingStopHandler else {
                return
            }
            log.warning("Tunnel not responding after \(self.shutdownTimeout) milliseconds, forcing stop")
            self.flushLog()
            pendingHandler()
        }
        tunnelQueue.sync {
            proxy.shutdown(error: nil)
        }
    }
    
    /// :nodoc:
    open override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        var response: Data?
        switch Message(messageData) {
        case .requestLog:
            response = memoryLog.description.data(using: .utf8)

        case .dataCount:
            if let proxy = proxy {
                response = Data()
                response?.append(UInt64(proxy.bytesIn))
                response?.append(UInt64(proxy.bytesOut))
            }
            
        default:
            break
        }
        completionHandler?(response)
    }
    
    // MARK: Connection (tunnel queue)
    
    private func connectTunnel(upgradedSocket: GenericSocket? = nil, preferredAddress: String? = nil) {
        log.info("Creating link session")
        
        // reuse upgraded socket
        if let upgradedSocket = upgradedSocket, !upgradedSocket.isShutdown {
            log.debug("Socket follows a path upgrade")
            connectTunnel(via: upgradedSocket)
            return
        }
        
        strategy.createSocket(from: self, timeout: dnsTimeout, preferredAddress: preferredAddress, queue: tunnelQueue) { (socket, error) in
            guard let socket = socket else {
                self.disposeTunnel(error: error)
                return
            }
            self.connectTunnel(via: socket)
        }
    }
    
    private func connectTunnel(via socket: GenericSocket) {
        log.info("Will connect to \(socket)")

        log.debug("Socket type is \(type(of: socket))")
        self.socket = socket
        self.socket?.delegate = self
        self.socket?.observe(queue: tunnelQueue, activeTimeout: socketTimeout)
    }
    
    private func finishTunnelDisconnection(error: Error?) {
        if let proxy = proxy, !(reasserting && proxy.canRebindLink()) {
            proxy.cleanup()
        }
        
        socket?.delegate = nil
        socket?.unobserve()
        socket = nil
        
        if let error = error {
            log.error("Tunnel did stop (error: \(error))")
        } else {
            log.info("Tunnel did stop on request")
        }
    }
    
    private func disposeTunnel(error: Error?) {
        flushLog()
        
        // failed to start
        if (pendingStartHandler != nil) {
            
            //
            // CAUTION
            //
            // passing nil to this callback will result in an extremely undesired situation,
            // because NetworkExtension would interpret it as "successfully connected to VPN"
            //
            // if we end up here disposing the tunnel with a pending start handled, we are
            // 100% sure that something wrong happened while starting the tunnel. in such
            // case, here we then must also make sure that an error object is ALWAYS
            // provided, so we do this with optional fallback to .socketActivity
            //
            // socketActivity makes sense, given that any other error would normally come
            // from SessionProxy.stopError. other paths to disposeTunnel() are only coming
            // from stopTunnel(), in which case we don't need to feed an error parameter to
            // the stop completion handler
            //
            pendingStartHandler?(error ?? ProviderError.socketActivity)
            pendingStartHandler = nil
        }
        // stopped intentionally
        else if (pendingStopHandler != nil) {
            pendingStopHandler?()
            pendingStopHandler = nil
        }
        // stopped externally, unrecoverable
        else {
            let fm = FileManager.default
            for key in [Configuration.Keys.ca, Configuration.Keys.clientCertificate, Configuration.Keys.clientKey] {
                try? fm.removeItem(at: temporaryURL(forKey: key))
            }
            cancelTunnelWithError(error)
        }
    }
}

extension TunnelKitProvider: GenericSocketDelegate {
    
    // MARK: GenericSocketDelegate (tunnel queue)
    
    func socketDidTimeout(_ socket: GenericSocket) {
        log.debug("Socket timed out waiting for activity, cancelling...")
        reasserting = true
        socket.shutdown()
    }
    
    func socketShouldChangeProtocol(_ socket: GenericSocket) {
        guard strategy.tryNextProtocol() else {
            disposeTunnel(error: ProviderError.exhaustedProtocols)
            return
        }
    }
    
    func socketDidBecomeActive(_ socket: GenericSocket) {
        guard let proxy = proxy else {
            return
        }
        if proxy.canRebindLink() {
            proxy.rebindLink(socket.link(withMTU: cfg.mtu))
            reasserting = false
        } else {
            proxy.setLink(socket.link(withMTU: cfg.mtu))
        }
    }
    
    func socket(_ socket: GenericSocket, didShutdownWithFailure failure: Bool) {
        guard let proxy = proxy else {
            return
        }
        
        var shutdownError: Error?
        if !failure {
            shutdownError = proxy.stopError
        } else {
            shutdownError = proxy.stopError ?? ProviderError.linkError
            linkFailures += 1
            log.debug("Link failures so far: \(linkFailures) (max = \(maxLinkFailures))")
        }
        
        // only try upgrade on network errors
        var upgradedSocket: GenericSocket? = nil
        if shutdownError as? SessionError == nil {
            upgradedSocket = socket.upgraded()
        }
        
        // treat negotiation timeout as socket timeout, UDP is connection-less
        if proxy.stopError as? SessionError == SessionError.negotiationTimeout {
            socketShouldChangeProtocol(socket)
        }

        finishTunnelDisconnection(error: shutdownError)
        if reasserting {
            guard (linkFailures < maxLinkFailures) else {
                log.debug("Too many link failures (\(linkFailures)), tunnel will die now")
                reasserting = false
                disposeTunnel(error: shutdownError)
                return
            }
            log.debug("Disconnection is recoverable, tunnel will reconnect in \(reconnectionDelay) milliseconds...")
            tunnelQueue.schedule(after: .milliseconds(reconnectionDelay)) {
                self.connectTunnel(upgradedSocket: upgradedSocket, preferredAddress: socket.remoteAddress)
            }
            return
        }
        disposeTunnel(error: shutdownError)
    }
    
    func socketHasBetterPath(_ socket: GenericSocket) {
        log.debug("Stopping tunnel due to a new better path")
        logCurrentSSID()
        proxy?.reconnect(error: ProviderError.networkChanged)
    }
}

extension TunnelKitProvider: SessionProxyDelegate {
    
    // MARK: SessionProxyDelegate (tunnel queue)
    
    /// :nodoc:
    public func sessionDidStart(_ proxy: SessionProxy, remoteAddress: String, reply: SessionReply) {
        reasserting = false
        
        log.info("Session did start")
        
        log.info("Returned ifconfig parameters:")
        log.info("\tRemote: \(remoteAddress)")
        log.info("\tIPv4: \(reply.ipv4?.description ?? "not configured")")
        log.info("\tIPv6: \(reply.ipv6?.description ?? "not configured")")
        log.info("\tDNS: \(reply.dnsServers)")
        
        bringNetworkUp(remoteAddress: remoteAddress, reply: reply) { (error) in
            if let error = error {
                log.error("Failed to configure tunnel: \(error)")
                self.pendingStartHandler?(error)
                self.pendingStartHandler = nil
                return
            }
            
            log.info("Tunnel interface is now UP")
            
            proxy.setTunnel(tunnel: NETunnelInterface(impl: self.packetFlow, isIPv6: reply.ipv6 != nil))

            self.pendingStartHandler?(nil)
            self.pendingStartHandler = nil
        }
    }
    
    /// :nodoc:
    public func sessionDidStop(_: SessionProxy, shouldReconnect: Bool) {
        log.info("Session did stop")

        if shouldReconnect {
            reasserting = true
        }
        socket?.shutdown()
    }
    
    private func bringNetworkUp(remoteAddress: String, reply: SessionReply, completionHandler: @escaping (Error?) -> Void) {
        
        // route all traffic to VPN
        var ipv4Settings: NEIPv4Settings?
        if let ipv4 = reply.ipv4 {
            let defaultRoute = NEIPv4Route.default()
            defaultRoute.gatewayAddress = ipv4.defaultGateway
            
            var routes: [NEIPv4Route] = [defaultRoute]
            for r in ipv4.routes {
                let ipv4Route = NEIPv4Route(destinationAddress: r.destination, subnetMask: r.mask)
                ipv4Route.gatewayAddress = r.gateway ?? ipv4.defaultGateway
                routes.append(ipv4Route)
            }
            
            ipv4Settings = NEIPv4Settings(addresses: [ipv4.address], subnetMasks: [ipv4.addressMask])
            ipv4Settings?.includedRoutes = routes
            ipv4Settings?.excludedRoutes = []
        }

        var ipv6Settings: NEIPv6Settings?
        if let ipv6 = reply.ipv6 {
            let defaultRoute = NEIPv6Route.default()
            defaultRoute.gatewayAddress = ipv6.defaultGateway

            var routes: [NEIPv6Route] = [defaultRoute]
            for r in ipv6.routes {
                let ipv6Route = NEIPv6Route(destinationAddress: r.destination, networkPrefixLength: r.prefixLength as NSNumber)
                ipv6Route.gatewayAddress = r.gateway ?? ipv6.defaultGateway
                routes.append(ipv6Route)
            }
            
            ipv6Settings = NEIPv6Settings(addresses: [ipv6.address], networkPrefixLengths: [ipv6.addressPrefixLength as NSNumber])
            ipv6Settings?.includedRoutes = [defaultRoute]
            ipv6Settings?.excludedRoutes = []
        }
        
        let dnsSettings = NEDNSSettings(servers: reply.dnsServers)
        
        let newSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: remoteAddress)
        if let _ = ipv6Settings {
            newSettings.ipv6Settings = ipv6Settings
        } else {
            newSettings.ipv4Settings = ipv4Settings
        }
        newSettings.dnsSettings = dnsSettings
        
        setTunnelNetworkSettings(newSettings, completionHandler: completionHandler)
    }
}

extension TunnelKitProvider {
    
    // MARK: Helpers
    
    private func configureLogging(debug: Bool, customFormat: String? = nil) {
        let logLevel: SwiftyBeaver.Level = (debug ? .debug : .info)
        let logFormat = customFormat ?? "$Dyyyy-MM-dd HH:mm:ss.SSS$d $L $N.$F:$l - $M"
        
        if debug {
            let console = ConsoleDestination()
            console.useNSLog = true
            console.minLevel = logLevel
            console.format = logFormat
            log.addDestination(console)
        }
        
        let memory = memoryLog
        memory.minLevel = logLevel
        memory.format = logFormat
        memory.maxLines = maxLogLines
        log.addDestination(memoryLog)
    }
    
    private func flushLog() {
        log.debug("Flushing log...")
        if let defaults = defaults, let key = cfg.debugLogKey {
            memoryLog.flush(to: defaults, with: key)
        }
    }
    
    private func logCurrentSSID() {
        if let ssid = observer.currentWifiNetworkName() {
            log.debug("Current SSID: '\(ssid)'")
        } else {
            log.debug("Current SSID: none (disconnected from WiFi)")
        }
    }
    
//    private func anyPointer(_ object: Any?) -> UnsafeMutableRawPointer {
//        let anyObject = object as AnyObject
//        return Unmanaged<AnyObject>.passUnretained(anyObject).toOpaque()
//    }
}
