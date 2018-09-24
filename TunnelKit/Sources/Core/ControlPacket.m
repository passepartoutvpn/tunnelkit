//
//  ControlPacket.m
//  TunnelKit
//
//  Created by Davide De Rosa on 9/14/18.
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

#import "ControlPacket.h"

@implementation ControlPacket

- (instancetype)initWithCode:(PacketCode)code
                         key:(uint8_t)key
                   sessionId:(NSData *)sessionId
                    packetId:(uint32_t)packetId
                     payload:(nullable NSData *)payload
{
    NSCParameterAssert(sessionId.length == PacketSessionIdLength);
    
    if (!(self = [super init])) {
        return nil;
    }
    _code = code;
    _key = key;
    _sessionId = sessionId;
    _packetId = packetId;
    _payload = payload;
    self.sentDate = nil;
    
    return self;
}

- (instancetype)initWithKey:(uint8_t)key
                  sessionId:(NSData *)sessionId
                     ackIds:(NSArray<NSNumber *> *)ackIds
         ackRemoteSessionId:(NSData *)ackRemoteSessionId
{
    NSCParameterAssert(sessionId.length == PacketSessionIdLength);
    NSCParameterAssert(ackRemoteSessionId.length == PacketSessionIdLength);
    
    if (!(self = [super init])) {
        return nil;
    }
    _packetId = UINT32_MAX; // bogus marker
    _code = PacketCodeAckV1;
    _key = key;
    _sessionId = sessionId;
    _ackIds = ackIds;
    _ackRemoteSessionId = ackRemoteSessionId;
    self.sentDate = nil;
    
    return self;
}

- (BOOL)isAck
{
    return (self.packetId == UINT32_MAX);
}

- (NSInteger)capacity
{
    const BOOL isAck = self.isAck;
    const NSUInteger ackLength = self.ackIds.count;
    NSCAssert(!isAck || ackLength > 0, @"Ack packet must provide positive ackLength");
    NSInteger n = PacketOpcodeLength + PacketSessionIdLength;
    n += PacketAckLengthLength;
    if (ackLength > 0) {
        n += ackLength * PacketIdLength + PacketSessionIdLength;
    }
    if (!isAck) {
        n += PacketIdLength;
    }
    n += self.payload.length;
    return n;
}

// Ruby: send_ctrl
- (NSInteger)serializeTo:(uint8_t *)to
{
    uint8_t *ptr = to;
    ptr += PacketHeaderSet(ptr, self.code, self.key, self.sessionId.bytes);
    if (self.ackIds.count > 0) {
        NSCParameterAssert(self.ackRemoteSessionId.length == PacketSessionIdLength);
        *ptr = self.ackIds.count;
        ptr += PacketAckLengthLength;
        for (NSNumber *n in self.ackIds) {
            const uint32_t ackId = (uint32_t)n.unsignedIntegerValue;
            *(uint32_t *)ptr = CFSwapInt32HostToBig(ackId);
            ptr += PacketIdLength;
        }
        memcpy(ptr, self.ackRemoteSessionId.bytes, PacketSessionIdLength);
        ptr += PacketSessionIdLength;
    }
    else {
        *ptr = 0; // no acks
        ptr += PacketAckLengthLength;
    }
    if (self.code != PacketCodeAckV1) {
        *(uint32_t *)ptr = CFSwapInt32HostToBig(self.packetId);
        ptr += PacketIdLength;
        if (self.payload) {
            memcpy(ptr, self.payload.bytes, self.payload.length);
            ptr += self.payload.length;
        }
    }
    return ptr - to;
}

- (NSData *)serialized
{
    NSMutableData *data = [[NSMutableData alloc] initWithLength:self.capacity];
    [self serializeTo:data.mutableBytes];
    return data;
}

@end
