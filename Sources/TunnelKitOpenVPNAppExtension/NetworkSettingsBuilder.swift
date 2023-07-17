//
//  NetworkSettingsBuilder.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 10/21/22.
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
import TunnelKitCore
import TunnelKitOpenVPNCore
import SwiftyBeaver

private let log = SwiftyBeaver.self

struct NetworkSettingsBuilder {
    let remoteAddress: String

    let localOptions: OpenVPN.Configuration

    let remoteOptions: OpenVPN.Configuration

    init(remoteAddress: String, localOptions: OpenVPN.Configuration, remoteOptions: OpenVPN.Configuration) {
        self.remoteAddress = remoteAddress
        self.localOptions = localOptions
        self.remoteOptions = remoteOptions
    }

    func build() -> NEPacketTunnelNetworkSettings {
        let ipv4Settings = computedIPv4Settings
        let ipv6Settings = computedIPv6Settings
        let dnsSettings = computedDNSSettings
        let proxySettings = computedProxySettings

        // add direct routes to DNS servers
        if !isGateway {
            for server in dnsSettings?.servers ?? [] {
                if server.contains(":") {
                    ipv6Settings?.includedRoutes?.insert(NEIPv6Route(destinationAddress: server, networkPrefixLength: 128), at: 0)
                } else {
                    ipv4Settings?.includedRoutes?.insert(NEIPv4Route(destinationAddress: server, subnetMask: "255.255.255.255"), at: 0)
                }
            }
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: remoteAddress)
        settings.ipv4Settings = ipv4Settings
        settings.ipv6Settings = ipv6Settings
        settings.dnsSettings = dnsSettings
        settings.proxySettings = proxySettings
        if let mtu = localOptions.mtu, mtu > 0 {
            settings.mtu = NSNumber(value: mtu)
        }
        return settings
    }
}

extension NetworkSettingsBuilder {
    private var pullRoutes: Bool {
        !(localOptions.noPullMask?.contains(.routes) ?? false)
    }

    private var pullDNS: Bool {
        !(localOptions.noPullMask?.contains(.dns) ?? false)
    }

    private var pullProxy: Bool {
        !(localOptions.noPullMask?.contains(.proxy) ?? false)
    }
}

extension NetworkSettingsBuilder {
    var isGateway: Bool {
        isIPv4Gateway || isIPv6Gateway
    }

    private var routingPolicies: [OpenVPN.RoutingPolicy]? {
        pullRoutes ? (remoteOptions.routingPolicies ?? localOptions.routingPolicies) : localOptions.routingPolicies
    }

    private var isIPv4Gateway: Bool {
        routingPolicies?.contains(.IPv4) ?? false
    }

    private var isIPv6Gateway: Bool {
        routingPolicies?.contains(.IPv6) ?? false
    }

    private var allRoutes4: [IPv4Settings.Route] {
        var routes = localOptions.routes4 ?? []
        if pullRoutes, let remoteRoutes = remoteOptions.routes4 {
            routes.append(contentsOf: remoteRoutes)
        }
        return routes
    }

    private var allRoutes6: [IPv6Settings.Route] {
        var routes = localOptions.routes6 ?? []
        if pullRoutes, let remoteRoutes = remoteOptions.routes6 {
            routes.append(contentsOf: remoteRoutes)
        }
        return routes
    }

    private var allDNSServers: [String] {
        var servers = localOptions.dnsServers ?? []
        if pullDNS, let remoteServers = remoteOptions.dnsServers {
            servers.append(contentsOf: remoteServers)
        }
        return servers
    }

    private var dnsDomain: String? {
        var domain = localOptions.dnsDomain
        if pullDNS, let remoteDomain = remoteOptions.dnsDomain {
            domain = remoteDomain
        }
        return domain
    }

    private var allDNSSearchDomains: [String] {
        var searchDomains = localOptions.searchDomains ?? []
        if pullDNS, let remoteSearchDomains = remoteOptions.searchDomains {
            searchDomains.append(contentsOf: remoteSearchDomains)
        }
        return searchDomains
    }

    private var allProxyBypassDomains: [String] {
        var bypass = localOptions.proxyBypassDomains ?? []
        if pullProxy, let remoteBypass = remoteOptions.proxyBypassDomains {
            bypass.append(contentsOf: remoteBypass)
        }
        return bypass
    }
}

extension NetworkSettingsBuilder {

    // IPv4/6 address/mask MUST come from server options
    // routes, instead, can both come from server and local options

    private var computedIPv4Settings: NEIPv4Settings? {
        guard let ipv4 = remoteOptions.ipv4 else {
            return nil
        }
        let ipv4Settings = NEIPv4Settings(addresses: [ipv4.address], subnetMasks: [ipv4.addressMask])
        var neRoutes: [NEIPv4Route] = []

        // route all traffic to VPN?
        if isIPv4Gateway {
            let defaultRoute = NEIPv4Route.default()
            defaultRoute.gatewayAddress = ipv4.defaultGateway
            neRoutes.append(defaultRoute)
            log.info("Routing.IPv4: Setting default gateway to \(ipv4.defaultGateway)")
        }

        for r in allRoutes4 {
            let ipv4Route = NEIPv4Route(destinationAddress: r.destination, subnetMask: r.mask)
            let gw = r.gateway ?? ipv4.defaultGateway
            ipv4Route.gatewayAddress = gw
            neRoutes.append(ipv4Route)
            log.info("Routing.IPv4: Adding route \(r.destination)/\(r.mask) -> \(gw)")
        }

        ipv4Settings.includedRoutes = neRoutes
        ipv4Settings.excludedRoutes = []
        return ipv4Settings
    }

    private var computedIPv6Settings: NEIPv6Settings? {
        guard let ipv6 = remoteOptions.ipv6 else {
            return nil
        }
        let ipv6Settings = NEIPv6Settings(addresses: [ipv6.address], networkPrefixLengths: [ipv6.addressPrefixLength as NSNumber])
        var neRoutes: [NEIPv6Route] = []

        // route all traffic to VPN?
        if isIPv6Gateway {
            let defaultRoute = NEIPv6Route.default()
            defaultRoute.gatewayAddress = ipv6.defaultGateway
            neRoutes.append(defaultRoute)
            log.info("Routing.IPv6: Setting default gateway to \(ipv6.defaultGateway)")
        }

        for r in allRoutes6 {
            let ipv6Route = NEIPv6Route(destinationAddress: r.destination, networkPrefixLength: r.prefixLength as NSNumber)
            let gw = r.gateway ?? ipv6.defaultGateway
            ipv6Route.gatewayAddress = gw
            neRoutes.append(ipv6Route)
            log.info("Routing.IPv6: Adding route \(r.destination)/\(r.prefixLength) -> \(gw)")
        }

        ipv6Settings.includedRoutes = neRoutes
        ipv6Settings.excludedRoutes = []
        return ipv6Settings
    }

    var hasGateway: Bool {
        var hasGateway = false
        if isIPv4Gateway && remoteOptions.ipv4 != nil {
            hasGateway = true
        }
        if isIPv6Gateway && remoteOptions.ipv6 != nil {
            hasGateway = true
        }
        return hasGateway
    }
}

extension NetworkSettingsBuilder {
    private var computedDNSSettings: NEDNSSettings? {
        guard localOptions.isDNSEnabled ?? true else {
            return nil
        }
        var dnsSettings: NEDNSSettings?
        switch localOptions.dnsProtocol {
        case .https:
            let dnsServers = localOptions.dnsServers ?? []
            guard let serverURL = localOptions.dnsHTTPSURL else {
                break
            }
            let specific = NEDNSOverHTTPSSettings(servers: dnsServers)
            specific.serverURL = serverURL
            dnsSettings = specific
            log.info("DNS over HTTPS: Using servers \(dnsServers)")
            log.info("\tHTTPS URL: \(serverURL)")

        case .tls:
            let dnsServers = localOptions.dnsServers ?? []
            guard let serverName = localOptions.dnsTLSServerName else {
                break
            }
            let specific = NEDNSOverTLSSettings(servers: dnsServers)
            specific.serverName = serverName
            dnsSettings = specific
            log.info("DNS over TLS: Using servers \(dnsServers)")
            log.info("\tTLS server name: \(serverName)")

        default:
            break
        }

        // fall back
        if dnsSettings == nil {
            let dnsServers = allDNSServers
            if !dnsServers.isEmpty {
                log.info("DNS: Using servers \(dnsServers)")
                dnsSettings = NEDNSSettings(servers: dnsServers)
            } else {
//                log.warning("DNS: No servers provided, using fall-back servers: \(fallbackDNSServers)")
//                dnsSettings = NEDNSSettings(servers: fallbackDNSServers)
                if isGateway {
                    log.warning("DNS: No settings provided")
                } else {
                    log.warning("DNS: No settings provided, using current network settings")
                }
            }
        }

        // "hack" for split DNS (i.e. use VPN only for DNS)
        if !isGateway {
            dnsSettings?.matchDomains = [""]
        }

        if let domain = dnsDomain {
            log.info("DNS: Using domain: \(domain)")
            dnsSettings?.domainName = domain
        }

        let searchDomains = allDNSSearchDomains
        if !searchDomains.isEmpty {
            log.info("DNS: Using search domains: \(searchDomains)")
            dnsSettings?.searchDomains = searchDomains
            if !isGateway {
                dnsSettings?.matchDomains = dnsSettings?.searchDomains
            }
        }

        return dnsSettings
    }
}

extension NetworkSettingsBuilder {
    private var computedProxySettings: NEProxySettings? {
        guard localOptions.isProxyEnabled ?? true else {
            return nil
        }
        var proxySettings: NEProxySettings?
        if let httpsProxy = pullProxy ? (remoteOptions.httpsProxy ?? localOptions.httpsProxy) : localOptions.httpsProxy {
            proxySettings = NEProxySettings()
            proxySettings?.httpsServer = httpsProxy.neProxy()
            proxySettings?.httpsEnabled = true
            log.info("Routing: Setting HTTPS proxy \(httpsProxy.address):\(httpsProxy.port)")
        }
        if let httpProxy = pullProxy ? (remoteOptions.httpProxy ?? localOptions.httpProxy) : localOptions.httpProxy {
            if proxySettings == nil {
                proxySettings = NEProxySettings()
            }
            proxySettings?.httpServer = httpProxy.neProxy()
            proxySettings?.httpEnabled = true
            log.info("Routing: Setting HTTP proxy \(httpProxy.address):\(httpProxy.port)")
        }
        if let pacURL = pullProxy ? (remoteOptions.proxyAutoConfigurationURL ?? localOptions.proxyAutoConfigurationURL) : localOptions.proxyAutoConfigurationURL {
            if proxySettings == nil {
                proxySettings = NEProxySettings()
            }
            proxySettings?.proxyAutoConfigurationURL = pacURL
            proxySettings?.autoProxyConfigurationEnabled = true
            log.info("Routing: Setting PAC \(pacURL)")
        }

        // only set if there is a proxy (proxySettings set to non-nil above)
        if proxySettings != nil {
            let bypass = allProxyBypassDomains
            if !bypass.isEmpty {
                proxySettings?.exceptionList = bypass
                log.info("Routing: Setting proxy by-pass list: \(bypass)")
            }
        }
        return proxySettings
    }
}

private extension Proxy {
    func neProxy() -> NEProxyServer {
        return NEProxyServer(address: address, port: Int(port))
    }
}
