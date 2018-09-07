//
//  SessionProxy.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 2/3/17.
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

import Foundation
import SwiftyBeaver
import __TunnelKitNative

private let log = SwiftyBeaver.self

private extension Error {
    func isTunnelError() -> Bool {
        let te = self as NSError
        return te.domain == TunnelKitErrorDomain
    }
    
    func isDataPathOverflow() -> Bool {
        let te = self as NSError
        return te.domain == TunnelKitErrorDomain && te.code == TunnelKitErrorCode.dataPathOverflow.rawValue
    }
}

/// Observes major events notified by a `SessionProxy`.
public protocol SessionProxyDelegate: class {

    /**
     Called after starting a session.

     - Parameter remoteAddress: The address of the VPN server.
     - Parameter reply: The compound `SessionReply` containing tunnel settings.
     */
    func sessionDidStart(_: SessionProxy, remoteAddress: String, reply: SessionReply)
    
    /**
     Called after stopping a session.
     
     - Parameter shouldReconnect: When `true`, the session can/should be restarted. Usually because the stop reason was recoverable.
     - Seealso: `SessionProxy.reconnect(...)`
     */
    func sessionDidStop(_: SessionProxy, shouldReconnect: Bool)
}

/// Provides methods to set up and maintain an OpenVPN session.
public class SessionProxy {
    private enum StopMethod {
        case shutdown
        
        case reconnect
    }
    
    // MARK: Configuration
    
    private let configuration: Configuration
    
    /// An optional `SessionProxyDelegate` for receiving session events.
    public weak var delegate: SessionProxyDelegate?
    
    // MARK: State

    private let queue: DispatchQueue

    private var tlsObserver: NSObjectProtocol?

    private var keys: [UInt8: SessionKey]

    private var oldKeys: [SessionKey]

    private var negotiationKeyIdx: UInt8
    
    private var currentKeyIdx: UInt8?
    
    private var negotiationKey: SessionKey {
        guard let key = keys[negotiationKeyIdx] else {
            fatalError("Keys are empty or index \(negotiationKeyIdx) not found in \(keys.keys)")
        }
        return key
    }
    
    private var currentKey: SessionKey? {
        guard let i = currentKeyIdx else {
            return nil
        }
        return keys[i]
    }
    
    private var link: LinkInterface?
    
    private var tunnel: TunnelInterface?
    
    private var isReliableLink: Bool {
        return link?.isReliable ?? false
    }

    private var sessionId: Data?
    
    private var remoteSessionId: Data?

    private var pushReply: SessionReply?
    
    private var nextPushRequestDate: Date?
    
    private var connectedDate: Date?

    private var lastPingOut: Date
    
    private var lastPingIn: Date
    
    private var isStopping: Bool
    
    /// The optional reason why the session stopped.
    public private(set) var stopError: Error?
    
    // MARK: Control
    
    private let controlPlainBuffer: ZeroingData

    private var controlQueueOut: [CommonPacket]

    private var controlQueueIn: [CommonPacket]

    private var controlPendingAcks: Set<UInt32>
    
    private var controlPacketIdOut: UInt32

    private var controlPacketIdIn: UInt32
    
    private var authenticator: Authenticator?
    
    // MARK: Data
    
    private(set) var bytesIn: Int
    
    private(set) var bytesOut: Int
    
    // MARK: Init

    /**
     Creates a VPN session.
     
     - Parameter queue: The `DispatchQueue` where to run the session loop.
     - Parameter configuration: The `SessionProxy.Configuration` to use for this session.
     */
    public init(queue: DispatchQueue, configuration: Configuration) throws {
        self.queue = queue
        self.configuration = configuration

        keys = [:]
        oldKeys = []
        negotiationKeyIdx = 0
        lastPingOut = Date.distantPast
        lastPingIn = Date.distantPast
        isStopping = false
        
        controlPlainBuffer = Z(count: TLSBoxMaxBufferLength)
        controlQueueOut = []
        controlQueueIn = []
        controlPendingAcks = []
        controlPacketIdOut = 0
        controlPacketIdIn = 0
        bytesIn = 0
        bytesOut = 0
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: Public interface

    /**
     Establishes the link interface for this session. The interface must be up and running for sending and receiving packets.
     
     - Precondition: `link` is an active network interface.
     - Postcondition: The VPN negotiation is started.
     - Parameter link: The `LinkInterface` on which to establish the VPN session.
     */
    public func setLink(_ link: LinkInterface) {
        guard (self.link == nil) else {
            log.warning("Link interface already set!")
            return
        }

        log.debug("Starting VPN session")
        
        // WARNING: runs in notification source queue (we know it's "queue", but better be safe than sorry)
        tlsObserver = NotificationCenter.default.addObserver(forName: .TLSBoxPeerVerificationError, object: nil, queue: nil) { (notification) in
            self.queue.async {
                self.deferStop(.shutdown, SessionError.peerVerification)
            }
        }
        
        self.link = link
        start()
    }
    
    /**
     Returns `true` if the current session can rebind to a new link with `rebindLink(...)`.

     - Returns: `true` if supports link rebinding.
     */
    public func canRebindLink() -> Bool {
        return (pushReply?.peerId != nil)
    }
    
    /**
     Rebinds the session to a new link if supported.
     
     - Precondition: `link` is an active network interface.
     - Postcondition: The VPN session is active.
     - Parameter link: The `LinkInterface` on which to establish the VPN session.
     - Seealso: `canRebindLink()`.
     */
    public func rebindLink(_ link: LinkInterface) {
        guard let _ = pushReply?.peerId else {
            log.warning("Session doesn't support link rebinding!")
            return
        }

        isStopping = false
        stopError = nil

        log.debug("Rebinding VPN session to a new link")
        self.link = link
        loopLink()
    }

    /**
     Establishes the tunnel interface for this session. The interface must be up and running for sending and receiving packets.
     
     - Precondition: `tunnel` is an active network interface.
     - Postcondition: The VPN data channel is open.
     - Parameter tunnel: The `TunnelInterface` on which to exchange the VPN data traffic.
     */
    public func setTunnel(tunnel: TunnelInterface) {
        guard (self.tunnel == nil) else {
            log.warning("Tunnel interface already set!")
            return
        }
        self.tunnel = tunnel
        loopTunnel()
    }

    /**
     Shuts down the session with an optional `Error` reason. Does nothing if the session is already stopped or about to stop.
     
     - Parameter error: An optional `Error` being the reason of the shutdown.
     */
    public func shutdown(error: Error?) {
        guard !isStopping else {
            log.warning("Ignore stop request, already stopping!")
            return
        }
        deferStop(.shutdown, error)
    }
    
    /**
     Shuts down the session with an optional `Error` reason and signals a reconnect flag to `SessionProxyDelegate.sessionDidStop(...)`. Does nothing if the session is already stopped or about to stop.
     
     - Parameter error: An optional `Error` being the reason of the shutdown.
     - Seealso: `SessionProxyDelegate.sessionDidStop(...)`
     */
    public func reconnect(error: Error?) {
        guard !isStopping else {
            log.warning("Ignore stop request, already stopping!")
            return
        }
        deferStop(.reconnect, error)
    }
    
    // Ruby: cleanup
    /**
     Cleans up the session resources.
     */
    public func cleanup() {
        log.info("Cleaning up...")

        if let observer = tlsObserver {
            NotificationCenter.default.removeObserver(observer)
            tlsObserver = nil
        }
        
        keys.removeAll()
        oldKeys.removeAll()
        negotiationKeyIdx = 0
        currentKeyIdx = nil
        
        sessionId = nil
        remoteSessionId = nil
        nextPushRequestDate = nil
        connectedDate = nil
        authenticator = nil
        pushReply = nil
        link = nil
        if !(tunnel?.isPersistent ?? false) {
            tunnel = nil
        }
        
        isStopping = false
        stopError = nil
    }

    // MARK: Loop

    // Ruby: start
    private func start() {
        loopLink()
        hardReset()

        guard !keys.isEmpty else {
            fatalError("Main loop must follow hard reset, keys are empty!")
        }

        loopNegotiation()
    }
    
    private func loopNegotiation() {
        guard let link = link else {
            return
        }
        guard !keys.isEmpty else {
            return
        }

        guard !negotiationKey.didHardResetTimeOut(link: link) else {
            doReconnect(error: SessionError.negotiationTimeout)
            return
        }
        guard !negotiationKey.didNegotiationTimeOut(link: link) else {
            doShutdown(error: SessionError.negotiationTimeout)
            return
        }
            
        if !isReliableLink {
            pushRequest()
            flushControlQueue()
        }
        
        guard (negotiationKey.controlState == .connected) else {
            queue.asyncAfter(deadline: .now() + CoreConfiguration.tickInterval) { [weak self] in
                self?.loopNegotiation()
            }
            return
        }

        // let loop die when negotiation is complete
    }

    // Ruby: udp_loop
    private func loopLink() {
        let loopedLink = link
        loopedLink?.setReadHandler(queue: queue) { [weak self] (newPackets, error) in
            guard loopedLink === self?.link else {
                log.warning("Ignoring read from outdated LINK")
                return
            }
            if let error = error {
                log.error("Failed LINK read: \(error)")
                return
            }
            
            if let packets = newPackets, !packets.isEmpty {
                self?.maybeRenegotiate()

//                log.verbose("Received \(packets.count) packets from LINK")
                self?.receiveLink(packets: packets)
            }
        }
    }

    // Ruby: tun_loop
    private func loopTunnel() {
        tunnel?.setReadHandler(queue: queue) { [weak self] (newPackets, error) in
            if let error = error {
                log.error("Failed TUN read: \(error)")
                return
            }

            if let packets = newPackets, !packets.isEmpty {
//                log.verbose("Received \(packets.count) packets from \(self.tunnelName)")
                self?.receiveTunnel(packets: packets)
            }
        }
    }

    // Ruby: recv_link
    private func receiveLink(packets: [Data]) {
        guard shouldHandlePackets() else {
            return
        }
        
        lastPingIn = Date()

        var dataPacketsByKey = [UInt8: [Data]]()
        
        for packet in packets {
//            log.verbose("Received data from LINK (\(packet.count) bytes): \(packet.toHex())")

            guard let firstByte = packet.first else {
                log.warning("Dropped malformed packet (missing header)")
                continue
            }
            let codeValue = firstByte >> 3
            guard let code = PacketCode(rawValue: codeValue) else {
                log.warning("Dropped malformed packet (unknown code: \(codeValue))")
                continue
            }
            let key = firstByte & 0b111

//            log.verbose("Parsed packet with (code, key) = (\(code.rawValue), \(key))")
            
            var offset = 1
            if (code == .dataV2) {
                guard packet.count >= offset + ProtocolMacros.peerIdLength else {
                    log.warning("Dropped malformed packet (missing peerId)")
                    continue
                }
                offset += ProtocolMacros.peerIdLength
            }

            if (code == .dataV1) || (code == .dataV2) {
                guard let _ = keys[key] else {
                    log.error("Key with id \(key) not found")
                    deferStop(.shutdown, SessionError.badKey)
                    return
                }

                // XXX: improve with array reference
                var dataPackets = dataPacketsByKey[key] ?? [Data]()
                dataPackets.append(packet)
                dataPacketsByKey[key] = dataPackets

                continue
            }
            
            guard packet.count >= offset + ProtocolMacros.sessionIdLength else {
                log.warning("Dropped malformed packet (missing sessionId)")
                continue
            }
            let sessionId = packet.subdata(offset: offset, count: ProtocolMacros.sessionIdLength)
            offset += ProtocolMacros.sessionIdLength
            
            guard packet.count >= offset + 1 else {
                log.warning("Dropped malformed packet (missing ackSize)")
                continue
            }
            let ackSize = packet[offset]
            offset += 1

            log.debug("Packet has code \(code.rawValue), key \(key), sessionId \(sessionId.toHex()) and \(ackSize) acks entries")

            if (ackSize > 0) {
                guard packet.count >= (offset + Int(ackSize) * ProtocolMacros.packetIdLength) else {
                    log.warning("Dropped malformed packet (missing acks)")
                    continue
                }
                var ackedPacketIds = [UInt32]()
                for _ in 0..<ackSize {
                    let ackedPacketId = packet.networkUInt32Value(from: offset)
                    ackedPacketIds.append(ackedPacketId)
                    offset += ProtocolMacros.packetIdLength
                }

                guard packet.count >= offset + ProtocolMacros.sessionIdLength else {
                    log.warning("Dropped malformed packet (missing remoteSessionId)")
                    continue
                }
                let remoteSessionId = packet.subdata(offset: offset, count: ProtocolMacros.sessionIdLength)
                offset += ProtocolMacros.sessionIdLength

                log.debug("Server acked packetIds \(ackedPacketIds) with remoteSessionId \(remoteSessionId.toHex())")

                handleAcks(ackedPacketIds, remoteSessionId: remoteSessionId)
            }

            if (code == .ackV1) {
                continue
            }

            guard packet.count >= offset + ProtocolMacros.packetIdLength else {
                log.warning("Dropped malformed packet (missing packetId)")
                continue
            }
            let packetId = packet.networkUInt32Value(from: offset)
            log.debug("Control packet has packetId \(packetId)")
            offset += ProtocolMacros.packetIdLength

            sendAck(key: key, packetId: packetId, remoteSessionId: sessionId)

            var payload: Data?
            if (offset < packet.count) {
                payload = packet.subdata(in: offset..<packet.count)

                if let payload = payload {
                    if CoreConfiguration.logsSensitiveData {
                        log.debug("Control packet payload (\(payload.count) bytes): \(payload.toHex())")
                    } else {
                        log.debug("Control packet payload (\(payload.count) bytes)")
                    }
                }
            }

            let controlPacket = CommonPacket(packetId, code, key, sessionId, payload)
            controlQueueIn.append(controlPacket)
            controlQueueIn.sort { $0.packetId < $1.packetId }
            
            for queuedControlPacket in controlQueueIn {
                if (queuedControlPacket.packetId < controlPacketIdIn) {
                    controlQueueIn.removeFirst()
                    continue
                }
                if (queuedControlPacket.packetId != controlPacketIdIn) {
                    continue
                }

                handleControlPacket(queuedControlPacket)

                controlPacketIdIn += 1
                controlQueueIn.removeFirst()
            }
        }

        // send decrypted packets to tunnel all at once
        for (keyId, dataPackets) in dataPacketsByKey {
            guard let sessionKey = keys[keyId] else {
                log.warning("Accounted a data packet for which the cryptographic key hadn't been found")
                continue
            }
            handleDataPackets(dataPackets, key: sessionKey)
        }
    }
    
    // Ruby: recv_tun
    private func receiveTunnel(packets: [Data]) {
        guard shouldHandlePackets() else {
            return
        }
        sendDataPackets(packets)
        lastPingOut = Date()
    }
    
    // Ruby: ping
    private func ping() {
        guard (currentKey?.controlState == .connected) else {
            return
        }
        
        let now = Date()
        guard (now.timeIntervalSince(lastPingIn) <= CoreConfiguration.pingTimeout) else {
            deferStop(.shutdown, SessionError.pingTimeout)
            return
        }

        if let interval = configuration.keepAliveInterval {
            let elapsed = now.timeIntervalSince(lastPingOut)
            guard (elapsed >= interval) else {
                let remaining = min(interval, interval - elapsed)
                queue.asyncAfter(deadline: .now() + remaining) { [weak self] in
                    self?.ping()
                }
                return
            }
        }

        log.debug("Send ping")
        sendDataPackets([DataPacket.pingString])
        lastPingOut = Date()

        if let interval = configuration.keepAliveInterval {
            queue.asyncAfter(deadline: .now() + interval) { [weak self] in
                self?.ping()
            }
        }
    }
    
    // MARK: Handshake
    
    // Ruby: reset_ctrl
    private func resetControlChannel() {
        controlPlainBuffer.zero()
        controlQueueOut.removeAll()
        controlQueueIn.removeAll()
        controlPendingAcks.removeAll()
        controlPacketIdOut = 0
        controlPacketIdIn = 0
        authenticator = nil
        bytesIn = 0
        bytesOut = 0
    }
    
    // Ruby: hard_reset
    private func hardReset() {
        log.debug("Send hard reset")

        resetControlChannel()
        pushReply = nil
        do {
            try sessionId = SecureRandom.data(length: ProtocolMacros.sessionIdLength)
        } catch let e {
            deferStop(.shutdown, e)
            return
        }
        negotiationKeyIdx = 0
        let newKey = SessionKey(id: UInt8(negotiationKeyIdx))
        keys[negotiationKeyIdx] = newKey
        log.debug("Negotiation key index is \(negotiationKeyIdx)")

        negotiationKey.state = .hardReset
        enqueueControlPackets(code: .hardResetClientV2, key: UInt8(negotiationKeyIdx), payload: Data())
    }
    
    // Ruby: soft_reset
    private func softReset() {
        log.debug("Send soft reset")
        
        resetControlChannel()
        negotiationKeyIdx = max(1, (negotiationKeyIdx + 1) % ProtocolMacros.numberOfKeys)
        let newKey = SessionKey(id: UInt8(negotiationKeyIdx))
        keys[negotiationKeyIdx] = newKey
        log.debug("Negotiation key index is \(negotiationKeyIdx)")

        negotiationKey.state = .softReset
        negotiationKey.softReset = true
        loopNegotiation()
        enqueueControlPackets(code: .softResetV1, key: UInt8(negotiationKeyIdx), payload: Data())
    }
    
    // Ruby: on_tls_connect
    private func onTLSConnect() {
        log.debug("TLS.connect: Handshake is complete")

        negotiationKey.controlState = .preAuth
        
        do {
            authenticator = try Authenticator(configuration.username, pushReply?.authToken ?? configuration.password)
            try authenticator?.putAuth(into: negotiationKey.tls)
        } catch let e {
            deferStop(.shutdown, e)
            return
        }

        guard let cipherTextOut = try? negotiationKey.tls.pullCipherText() else {
            log.verbose("TLS.auth: Still can't pull ciphertext")
            return
        }

        log.debug("TLS.auth: Pulled ciphertext (\(cipherTextOut.count) bytes)")
        enqueueControlPackets(code: .controlV1, key: negotiationKey.id, payload: cipherTextOut)
    }
    
    // Ruby: push_request
    private func pushRequest() {
        guard (negotiationKey.controlState == .preIfConfig) else {
            return
        }
        if !isReliableLink {
            guard let targetDate = nextPushRequestDate, (Date() > targetDate) else {
                return
            }
        }
        
        log.debug("TLS.ifconfig: Put plaintext (PUSH_REQUEST)")
        try? negotiationKey.tls.putPlainText("PUSH_REQUEST\0")
        
        guard let cipherTextOut = try? negotiationKey.tls.pullCipherText() else {
            log.verbose("TLS.ifconfig: Still can't pull ciphertext")
            return
        }
        
        log.debug("TLS.ifconfig: Send pulled ciphertext (\(cipherTextOut.count) bytes)")
        enqueueControlPackets(code: .controlV1, key: negotiationKey.id, payload: cipherTextOut)
        
        if negotiationKey.softReset {
            completeConnection()
        }
        nextPushRequestDate = Date().addingTimeInterval(CoreConfiguration.retransmissionLimit)
    }
    
    private func maybeRenegotiate() {
        guard let renegotiatesAfter = configuration.renegotiatesAfter, renegotiatesAfter > 0 else {
            return
        }
        guard (negotiationKeyIdx == currentKeyIdx) else {
            return
        }
        
        let elapsed = -negotiationKey.startTime.timeIntervalSinceNow
        if (elapsed > renegotiatesAfter) {
            log.debug("Renegotiating after \(elapsed) seconds")
            softReset()
        }
    }
    
    private func completeConnection() {
        setupEncryption()
        authenticator = nil
        negotiationKey.controlState = .connected
        connectedDate = Date()
        transitionKeys()
    }
    
    // MARK: Control

    // Ruby: handle_ctrl_pkt
    private func handleControlPacket(_ packet: CommonPacket) {
        guard (packet.key == negotiationKey.id) else {
            log.error("Bad key in control packet (\(packet.key) != \(negotiationKey.id))")
//            deferStop(.shutdown, SessionError.badKey)
            return
        }
        
        log.debug("Handle control packet with code \(packet.code.rawValue) and id \(packet.packetId)")

        if (((packet.code == .hardResetServerV2) && (negotiationKey.state == .hardReset)) ||
            ((packet.code == .softResetV1) && (negotiationKey.state == .softReset))) {
            
            if (negotiationKey.state == .hardReset) {
                guard let sessionId = packet.sessionId else {
                    deferStop(.shutdown, SessionError.missingSessionId)
                    return
                }
                remoteSessionId = sessionId
            }
            guard let remoteSessionId = remoteSessionId else {
                log.error("No remote session id")
                deferStop(.shutdown, SessionError.missingSessionId)
                return
            }
            guard (packet.sessionId == remoteSessionId) else {
                if let packetSessionId = packet.sessionId {
                    log.error("Packet session mismatch (\(packetSessionId.toHex()) != \(remoteSessionId.toHex()))")
                }
                deferStop(.shutdown, SessionError.sessionMismatch)
                return
            }

            negotiationKey.state = .tls

            log.debug("Remote sessionId is \(remoteSessionId.toHex())")
            log.debug("Start TLS handshake")

            negotiationKey.tlsOptional = TLSBox(
                caPath: configuration.caPath,
                clientCertificatePath: configuration.clientCertificatePath,
                clientKeyPath: configuration.clientKeyPath
            )
            do {
                try negotiationKey.tls.start()
            } catch let e {
                deferStop(.shutdown, e)
                return
            }

            guard let cipherTextOut = try? negotiationKey.tls.pullCipherText() else {
                deferStop(.shutdown, SessionError.tlsError)
                return
            }

            log.debug("TLS.connect: Pulled ciphertext (\(cipherTextOut.count) bytes)")
            enqueueControlPackets(code: .controlV1, key: negotiationKey.id, payload: cipherTextOut)
        }
        else if ((packet.code == .controlV1) && (negotiationKey.state == .tls)) {
            guard let remoteSessionId = remoteSessionId else {
                deferStop(.shutdown, SessionError.missingSessionId)
                return
            }
            guard (packet.sessionId == remoteSessionId) else {
                if let packetSessionId = packet.sessionId {
                    log.error("Packet session mismatch (\(packetSessionId.toHex()) != \(remoteSessionId.toHex()))")
                }
                deferStop(.shutdown, SessionError.sessionMismatch)
                return
            }
            
            guard let cipherTextIn = packet.payload else {
                log.warning("TLS.connect: Control packet with empty payload?")
                return
            }

            log.debug("TLS.connect: Put received ciphertext (\(cipherTextIn.count) bytes)")
            try? negotiationKey.tls.putCipherText(cipherTextIn)

            if let cipherTextOut = try? negotiationKey.tls.pullCipherText() {
                log.debug("TLS.connect: Send pulled ciphertext (\(cipherTextOut.count) bytes)")
                enqueueControlPackets(code: .controlV1, key: negotiationKey.id, payload: cipherTextOut)
            }
            
            if negotiationKey.shouldOnTLSConnect() {
                onTLSConnect()
            }

            do {
                var length = 0
                try negotiationKey.tls.pullRawPlainText(controlPlainBuffer.mutableBytes, length: &length)

                let controlData = controlPlainBuffer.withOffset(0, count: length)
                handleControlData(controlData)
            } catch _ {
            }
        }
    }

    // Ruby: handle_ctrl_data
    private func handleControlData(_ data: ZeroingData) {
        guard let auth = authenticator else { return }

        if CoreConfiguration.logsSensitiveData {
            log.debug("Pulled plain control data (\(data.count) bytes): \(data.toHex())")
        } else {
            log.debug("Pulled plain control data (\(data.count) bytes)")
        }

        auth.appendControlData(data)

        if (negotiationKey.controlState == .preAuth) {
            do {
                guard try auth.parseAuthReply() else {
                    return
                }
            } catch let e {
                deferStop(.shutdown, e)
                return
            }
            
            negotiationKey.controlState = .preIfConfig
            nextPushRequestDate = Date().addingTimeInterval(negotiationKey.softReset ? CoreConfiguration.softResetDelay : CoreConfiguration.retransmissionLimit)
            pushRequest()
        }
        
        for message in auth.parseMessages() {
            if CoreConfiguration.logsSensitiveData {
                log.debug("Parsed control message (\(message.count) bytes): \"\(message)\"")
            } else {
                log.debug("Parsed control message (\(message.count) bytes)")
            }
            handleControlMessage(message)
        }
    }

    // Ruby: handle_ctrl_msg
    private func handleControlMessage(_ message: String) {
        guard !message.hasPrefix("AUTH_FAILED") else {
            deferStop(.shutdown, SessionError.badCredentials)
            return
        }
        
        guard (negotiationKey.controlState == .preIfConfig) else {
            return
        }

        if CoreConfiguration.logsSensitiveData {
            log.debug("Received control message: \"\(message)\"")
        }
        
        let reply: PushReply
        do {
            guard let optionalReply = try PushReply(message: message) else {
                return
            }
            reply = optionalReply
            log.debug("Received PUSH_REPLY: \"\(reply)\"")
        } catch let e {
            deferStop(.shutdown, e)
            return
        }
        
        pushReply = reply
        completeConnection()

        guard let remoteAddress = link?.remoteAddress else {
            fatalError("Could not resolve link remote address")
        }
        delegate?.sessionDidStart(self, remoteAddress: remoteAddress, reply: reply)

        if let interval = configuration.keepAliveInterval {
            queue.asyncAfter(deadline: .now() + interval) { [weak self] in
                self?.ping()
            }
        }
    }
    
    // Ruby: transition_keys
    private func transitionKeys() {
        if let key = currentKey {
            oldKeys.append(key)
        }
        currentKeyIdx = negotiationKeyIdx
        cleanKeys()
    }
    
    // Ruby: clean_keys
    private func cleanKeys() {
        while (oldKeys.count > 1) {
            let key = oldKeys.removeFirst()
            keys.removeValue(forKey: key.id)
        }
    }
    
    // Ruby: q_ctrl
    private func enqueueControlPackets(code: PacketCode, key: UInt8, payload: Data) {
        guard let link = link else {
            log.warning("Not writing to LINK, interface is down")
            return
        }
        
        let oldIdOut = controlPacketIdOut
        let maxCount = link.mtu
        var queuedCount = 0
        var offset = 0
        
        repeat {
            let subPayloadLength = min(maxCount, payload.count - offset)
            let subPayloadData = payload.subdata(offset: offset, count: subPayloadLength)
            let packet = CommonPacket(controlPacketIdOut, code, key, sessionId, subPayloadData)
            
            controlQueueOut.append(packet)
            controlPacketIdOut += 1
            offset += maxCount
            queuedCount += subPayloadLength
        } while (offset < payload.count)
        
        assert(queuedCount == payload.count)
        
        let packetCount = controlPacketIdOut - oldIdOut
        if (packetCount > 1) {
            log.debug("Enqueued \(packetCount) control packets [\(oldIdOut)-\(controlPacketIdOut - 1)]")
        } else {
            log.debug("Enqueued 1 control packet [\(oldIdOut)]")
        }
        
        flushControlQueue()
    }
    
    // Ruby: flush_ctrl_q_out
    private func flushControlQueue() {
        for controlPacket in controlQueueOut {
            if let sentDate = controlPacket.sentDate {
                let timeAgo = -sentDate.timeIntervalSinceNow
                guard (timeAgo >= CoreConfiguration.retransmissionLimit) else {
                    log.debug("Skip control packet with id \(controlPacket.packetId) (sent on \(sentDate), \(timeAgo) seconds ago)")
                    continue
                }
            }

            log.debug("Send control packet with code \(controlPacket.code.rawValue)")

            if let payload = controlPacket.payload {
                if CoreConfiguration.logsSensitiveData {
                    log.debug("Control packet has payload (\(payload.count) bytes): \(payload.toHex())")
                } else {
                    log.debug("Control packet has payload (\(payload.count) bytes)")
                }
            }

            let raw = controlPacket.toBuffer()
            log.debug("Send control packet (\(raw.count) bytes): \(raw.toHex())")
            
            // track pending acks for sent packets
            controlPendingAcks.insert(controlPacket.packetId)

            // WARNING: runs in Network.framework queue
            link?.writePacket(raw) { [weak self] (error) in
                if let error = error {
                    self?.queue.sync {
                        log.error("Failed LINK write during control flush: \(error)")
                        self?.deferStop(.reconnect, SessionError.failedLinkWrite)
                        return
                    }
                }
            }
            controlPacket.sentDate = Date()
        }
//        log.verbose("Packets now pending ack: \(controlPendingAcks)")
    }
    
    // Ruby: setup_keys
    private func setupEncryption() {
        guard let auth = authenticator else {
            fatalError("Setting up encryption without having authenticated")
        }
        guard let sessionId = sessionId else {
            fatalError("Setting up encryption without a local sessionId")
        }
        guard let remoteSessionId = remoteSessionId else {
            fatalError("Setting up encryption without a remote sessionId")
        }
        guard let serverRandom1 = auth.serverRandom1, let serverRandom2 = auth.serverRandom2 else {
            fatalError("Setting up encryption without server randoms")
        }
        guard let pushReply = pushReply else {
            fatalError("Setting up encryption without a former PUSH_REPLY")
        }

        if CoreConfiguration.logsSensitiveData {
            log.debug("Set up encryption from the following components:")
            log.debug("\tpreMaster: \(auth.preMaster.toHex())")
            log.debug("\trandom1: \(auth.random1.toHex())")
            log.debug("\trandom2: \(auth.random2.toHex())")
            log.debug("\tserverRandom1: \(serverRandom1.toHex())")
            log.debug("\tserverRandom2: \(serverRandom2.toHex())")
            log.debug("\tsessionId: \(sessionId.toHex())")
            log.debug("\tremoteSessionId: \(remoteSessionId.toHex())")
        } else {
            log.debug("Set up encryption")
        }
        
        let pushedFraming = pushReply.compressionFraming
        if let negFraming = pushedFraming {
            log.debug("Negotiated compression framing: \(negFraming.rawValue)")
        }
        let pushedCipher = pushReply.cipher
        if let negCipher = pushedCipher {
            log.debug("Negotiated cipher: \(negCipher.rawValue)")
        }

        let bridge: EncryptionBridge
        do {
            bridge = try EncryptionBridge(
                pushedCipher ?? configuration.cipher,
                configuration.digest,
                auth,
                sessionId,
                remoteSessionId
            )
        } catch let e {
            deferStop(.shutdown, e)
            return
        }

        negotiationKey.dataPath = DataPath(
            encrypter: bridge.encrypter(),
            decrypter: bridge.decrypter(),
            peerId: pushReply.peerId ?? PacketPeerIdDisabled,
            compressionFraming: (pushedFraming ?? configuration.compressionFraming).native,
            maxPackets: link?.packetBufferSize ?? 200,
            usesReplayProtection: CoreConfiguration.usesReplayProtection
        )
    }
    
    // MARK: Data

    // Ruby: handle_data_pkt
    private func handleDataPackets(_ packets: [Data], key: SessionKey) {
        bytesIn += packets.flatCount
        do {
            guard let decryptedPackets = try key.decrypt(packets: packets) else {
                log.warning("Could not decrypt packets, is SessionKey properly configured (dataPath, peerId)?")
                return
            }
            guard !decryptedPackets.isEmpty else {
                return
            }

            tunnel?.writePackets(decryptedPackets, completionHandler: nil)
        } catch let e {
            guard !e.isTunnelError() else {
                deferStop(.shutdown, e)
                return
            }
            deferStop(.reconnect, e)
        }
    }
    
    // Ruby: send_data_pkt
    private func sendDataPackets(_ packets: [Data]) {
        guard let key = currentKey else {
            return
        }
        do {
            guard let encryptedPackets = try key.encrypt(packets: packets) else {
                log.warning("Could not encrypt packets, is SessionKey properly configured (dataPath, peerId)?")
                return
            }
            guard !encryptedPackets.isEmpty else {
                return
            }
            
            // WARNING: runs in Network.framework queue
            bytesOut += encryptedPackets.flatCount
            link?.writePackets(encryptedPackets) { [weak self] (error) in
                if let error = error {
                    self?.queue.sync {
                        log.error("Data: Failed LINK write during send data: \(error)")
                        self?.deferStop(.reconnect, SessionError.failedLinkWrite)
                        return
                    }
                }
//                log.verbose("Data: \(encryptedPackets.count) packets successfully written to LINK")
            }
        } catch let e {
            guard !e.isTunnelError() else {
                deferStop(.shutdown, e)
                return
            }
            deferStop(.reconnect, e)
        }
    }
    
    // MARK: Acks
    
    // Ruby: handle_acks
    private func handleAcks(_ packetIds: [UInt32], remoteSessionId: Data) {
        guard (remoteSessionId == sessionId) else {
            if let sessionId = sessionId {
                log.error("Ack session mismatch (\(remoteSessionId.toHex()) != \(sessionId.toHex()))")
            }
            deferStop(.shutdown, SessionError.sessionMismatch)
            return
        }
        
        // drop queued out packets if ack-ed
        for (i, controlPacket) in controlQueueOut.enumerated() {
            if packetIds.contains(controlPacket.packetId) {
                controlQueueOut.remove(at: i)
            }
        }

        // remove ack-ed packets from pending
        controlPendingAcks.subtract(packetIds)
//        log.verbose("Packets still pending ack: \(controlPendingAcks)")

        // retry PUSH_REQUEST if ack queue is empty (all sent packets were ack'ed)
        if (isReliableLink && controlPendingAcks.isEmpty) {
            pushRequest()
        }
    }
    
    // Ruby: send_ack
    private func sendAck(key: UInt8, packetId: UInt32, remoteSessionId: Data) {
        log.debug("Send ack for received packetId \(packetId)")

        var raw = PacketWithHeader(.ackV1, key, sessionId)
        raw.append(UInt8(1)) // ackSize
        raw.append(UInt32(packetId).bigEndian)
        raw.append(remoteSessionId)
        
        // WARNING: runs in Network.framework queue
        link?.writePacket(raw) { [weak self] (error) in
            if let error = error {
                self?.queue.sync {
                    log.error("Failed LINK write during send ack for packetId \(packetId): \(error)")
                    self?.deferStop(.reconnect, SessionError.failedLinkWrite)
                    return
                }
            }
            log.debug("Ack successfully written to LINK for packetId \(packetId)")
        }
    }
    
    // MARK: Stop
    
    private func shouldHandlePackets() -> Bool {
        return (!isStopping && !keys.isEmpty)
    }
    
    private func deferStop(_ method: StopMethod, _ error: Error?) {
        isStopping = true
        
        switch method {
        case .shutdown:
            doShutdown(error: error)
        
        case .reconnect:
            doReconnect(error: error)
        }
    }
    
    private func doShutdown(error: Error?) {
        if let error = error {
            log.error("Trigger shutdown (error: \(error))")
        } else {
            log.info("Trigger shutdown on request")
        }
        stopError = error
        delegate?.sessionDidStop(self, shouldReconnect: false)
    }
    
    private func doReconnect(error: Error?) {
        if let error = error {
            log.error("Trigger reconnection (error: \(error))")
        } else {
            log.info("Trigger reconnection on request")
        }
        stopError = error
        delegate?.sessionDidStop(self, shouldReconnect: true)
    }
}
