import TunnelKitWireGuardCore
import TunnelKitWireGuardManager
import WireGuardKit
import __TunnelKitUtils
import SwiftyBeaver

// SPDX-License-Identifier: MIT
// Copyright © 2018-2021 WireGuard LLC. All Rights Reserved.

import Foundation
import NetworkExtension
import os


extension Notification.Name {

}

open class WireGuardTunnelProvider: NEPacketTunnelProvider {
    private var cfg: WireGuard.ProviderConfiguration!
    
    /// The number of milliseconds between data count updates. Set to 0 to disable updates (default).
    public var dataCountInterval = 0

    /// Once the tunnel starts, enable this property to update connection stats
    private var tunnelIsStarted = false

    private let tunnelQueue = DispatchQueue(label: WireGuardTunnelProvider.description(), qos: .utility)

    private lazy var adapter: WireGuardAdapter = {
        return WireGuardAdapter(with: self) { logLevel, message in
            wg_log(logLevel.osLogLevel, message: message)
        }
    }()

    open override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // BEGIN: TunnelKit
        guard let tunnelProviderProtocol = protocolConfiguration as? NETunnelProviderProtocol else {
            fatalError("Not a NETunnelProviderProtocol")
        }
        guard let providerConfiguration = tunnelProviderProtocol.providerConfiguration else {
            fatalError("Missing providerConfiguration")
        }

        let tunnelConfiguration: TunnelConfiguration
        do {
            cfg = try fromDictionary(WireGuard.ProviderConfiguration.self, providerConfiguration)
            tunnelConfiguration = cfg.configuration.tunnelConfiguration
        } catch {
            completionHandler(TunnelKitWireGuardError.savedProtocolConfigurationIsInvalid)
            return
        }

        configureLogging()
        // END: TunnelKit

        // Start the tunnel
        adapter.start(tunnelConfiguration: tunnelConfiguration) { [weak self] adapterError in
            guard let adapterError = adapterError else {
                let interfaceName = self?.adapter.interfaceName ?? "unknown"

                wg_log(.info, message: "Tunnel interface is \(interfaceName)")
                self?.tunnelIsStarted = true
                self?.refreshDataCount()
                completionHandler(nil)
                return
            }

            switch adapterError {
            case .cannotLocateTunnelFileDescriptor:
                wg_log(.error, staticMessage: "Starting tunnel failed: could not determine file descriptor")
                self?.cfg._appexSetLastError(.couldNotDetermineFileDescriptor)
                completionHandler(TunnelKitWireGuardError.couldNotDetermineFileDescriptor)

            case .dnsResolution(let dnsErrors):
                let hostnamesWithDnsResolutionFailure = dnsErrors.map(\.address)
                    .joined(separator: ", ")
                wg_log(.error, message: "DNS resolution failed for the following hostnames: \(hostnamesWithDnsResolutionFailure)")
                self?.cfg._appexSetLastError(.dnsResolutionFailure)
                completionHandler(TunnelKitWireGuardError.dnsResolutionFailure)

            case .setNetworkSettings(let error):
                wg_log(.error, message: "Starting tunnel failed with setTunnelNetworkSettings returning \(error.localizedDescription)")
                self?.cfg._appexSetLastError(.couldNotSetNetworkSettings)
                completionHandler(TunnelKitWireGuardError.couldNotSetNetworkSettings)

            case .startWireGuardBackend(let errorCode):
                wg_log(.error, message: "Starting tunnel failed with wgTurnOn returning \(errorCode)")
                self?.cfg._appexSetLastError(.couldNotStartBackend)
                completionHandler(TunnelKitWireGuardError.couldNotStartBackend)

            case .invalidState:
                // Must never happen
                fatalError()
            }
        }
    }

    open override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        wg_log(.info, staticMessage: "Stopping tunnel")

        adapter.stop { [weak self] error in
            // BEGIN: TunnelKit
            self?.cfg._appexSetLastError(nil)
            self?.tunnelIsStarted = false
            self?.refreshDataCount()
            // END: TunnelKit

            if let error = error {
                wg_log(.error, message: "Failed to stop WireGuard adapter: \(error.localizedDescription)")
            }
            completionHandler()

            #if os(macOS)
            // HACK: This is a filthy hack to work around Apple bug 32073323 (dup'd by us as 47526107).
            // Remove it when they finally fix this upstream and the fix has been rolled out to
            // sufficient quantities of users.
            exit(0)
            #endif
        }
    }

    open override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        guard let completionHandler = completionHandler else { return }

        if messageData.count == 1 && messageData[0] == 0 {
            adapter.getRuntimeConfiguration { settings in
                var data: Data?
                if let settings = settings {
                    data = settings.data(using: .utf8)!
                }
                completionHandler(data)
            }
        } else {
            completionHandler(nil)
        }
    }

    // MARK: Data counter (tunnel queue)

    private func refreshDataCount() {
        guard dataCountInterval > 0 else { return }
        tunnelQueue.schedule(after: DispatchTimeInterval.milliseconds(dataCountInterval)) { [weak self] in
            self?.refreshDataCount()
        }
        
        guard tunnelIsStarted else {
            cfg._appexSetDataCount(nil)
            return
        }
        do {
            let dataCount = try getStats()
            cfg._appexSetDataCount(dataCount)
        } catch {
            wg_log(.error, message: "Failed to refresh data count \(error.localizedDescription)")
        }

    }
}

extension WireGuardTunnelProvider {
    private func configureLogging() {
        let logLevel: SwiftyBeaver.Level = (cfg.shouldDebug ? .debug : .info)
        let logFormat = cfg.debugLogFormat ?? "$Dyyyy-MM-dd HH:mm:ss.SSS$d $L $N.$F:$l - $M"

        if cfg.shouldDebug {
            let console = ConsoleDestination()
            console.useNSLog = true
            console.minLevel = logLevel
            console.format = logFormat
            SwiftyBeaver.addDestination(console)
        }

        let file = FileDestination(logFileURL: cfg._appexDebugLogURL)
        file.minLevel = logLevel
        file.format = logFormat
        file.logFileMaxSize = 20000
        SwiftyBeaver.addDestination(file)

        // store path for clients
        cfg._appexSetDebugLogPath()
    }

    func getStats() throws -> WireGuardDataCount {
        var result: String?

        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        adapter.getRuntimeConfiguration { string in
            result = string
            dispatchGroup.leave()
        }

        guard case .success = dispatchGroup.wait(wallTimeout: .now() + 1) else { throw StatsError.timeout }
        guard let result else { throw StatsError.nilValue }
        guard let newStats = WireGuardDataCount(from: result) else { throw StatsError.parse }

        return newStats
    }

    enum StatsError: LocalizedError {
        case timeout, nilValue, parse

        var errorDescription: String? {
            switch self {
            case .timeout:
                return "adapter.getRuntimeConfiguration() timeout."
            case .nilValue:
                return "Received nil string for stats."
            case .parse:
                return "Couldn't parse stats."
            }
        }
    }
}

extension WireGuardLogLevel {
    var osLogLevel: OSLogType {
        switch self {
        case .verbose:
            return .debug
        case .error:
            return .error
        }
    }
}

private extension WireGuardDataCount {
    init?(from string: String) {
        var bytesReceived: UInt64?
        var bytesSent: UInt64?

        string.enumerateLines { line, stop in
            if bytesReceived == nil, let value = parseValue("rx_bytes=", in: line) {
                bytesReceived = value
            } else if bytesSent == nil, let value = parseValue("tx_bytes=", in: line) {
                bytesSent = value
            }

            if bytesReceived != nil, bytesSent != nil {
                stop = true
            }
        }

        guard let bytesReceived, let bytesSent else {
            return nil
        }

        self.init(bytesReceived, bytesSent)
    }
}

@inline(__always) private func parseValue(_ prefixKey: String, in line: String) -> UInt64? {
    guard line.hasPrefix(prefixKey) else { return nil }

    let value = line.dropFirst(prefixKey.count)

    return UInt64(value)
}
