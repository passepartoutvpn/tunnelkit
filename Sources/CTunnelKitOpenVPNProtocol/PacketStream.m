//
//  PacketStream.m
//  TunnelKit
//
//  Created by Davide De Rosa on 4/25/19.
//  Copyright (c) 2022 Davide De Rosa. All rights reserved.
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

#import "PacketStream.h"

static const NSInteger PacketStreamHeaderLength = sizeof(uint16_t);

@implementation PacketStream

+ (void)xormask:(uint8_t *)dst src:(uint8_t *)src xorMask:(NSData *)xorMask length:(int)length
{
    if (((uint8_t *)(xorMask.bytes))[0] != 0) {
        for (int i = 0; i < length; ++i) {
            dst[i] = src[i] ^ ((uint8_t *)(xorMask.bytes))[i % xorMask.length];
        }
        return;
    }
    memcpy(dst, src, length);
}

+ (void)xorptrpos:(uint8_t *)dst src:(uint8_t *)src length:(int)length
{
    for (int i = 0; i < length; ++i) {
        dst[i] = src[i] ^ (i + 1);
    }
}

+ (void)reverse:(uint8_t *)dst src:(uint8_t *)src length:(int)length
{
    uint8_t temp = 0;
    dst[0] = src[0];
    for (int i = 1; i < length/2; ++i) {
        temp = dst[length - 1 - i];
        dst[length - 1 - i] = src[i];
        dst[i] = temp;
    }
}

+ (void)memcpyXor:(uint8_t *)dst src:(NSData *)src xorMask:(NSData *)xorMask xorMethod:(int)xorMethod mode:(int)mode
{
    uint8_t *source = (uint8_t *) src.bytes;
    switch (xorMethod) {
        case 0:
            memcpy(dst, source, src.length);
            break;
        case 1:
            [PacketStream xormask:dst src:source xorMask:xorMask length:src.length];
            break;
        case 2:
            [PacketStream xorptrpos:dst src:source length:src.length];
            break;
        case 3:
            [PacketStream reverse:dst src:source length:src.length];
            break;
        case 4:
            // 0 = read; 1 = write
            if (mode == 0) {
                [PacketStream xormask:dst src:source xorMask:xorMask length:src.length];
                [PacketStream xorptrpos:dst src:dst length:src.length];
                [PacketStream reverse:dst src:dst length:src.length];
                [PacketStream xorptrpos:dst src:dst length:src.length];
            } else {
                [PacketStream xorptrpos:dst src:source length:src.length];
                [PacketStream reverse:dst src:dst length:src.length];
                [PacketStream xorptrpos:dst src:dst length:src.length];
                [PacketStream xormask:dst src:dst xorMask:xorMask length:src.length];
            }
        default:
            break;
    }
}

+ (NSArray<NSData *> *)packetsFromStream:(NSData *)stream until:(NSInteger *)until xorMask:(NSData *)xorMask xorMethod:(int)xorMethod mode:(int)mode
{
    NSInteger ni = 0;
    NSMutableArray<NSData *> *parsed = [[NSMutableArray alloc] init];

    while (ni + PacketStreamHeaderLength <= stream.length) {
        const NSInteger packlen = CFSwapInt16BigToHost(*(uint16_t *)(stream.bytes + ni));
        const NSInteger start = ni + PacketStreamHeaderLength;
        const NSInteger end = start + packlen;
        if (end > stream.length) {
            break;
        }
        NSData *packet = [stream subdataWithRange:NSMakeRange(start, packlen)];
        uint8_t* packetBytes = (uint8_t*) packet.bytes;
        [PacketStream memcpyXor:packetBytes src:packet xorMask:xorMask xorMethod:xorMethod mode:mode];
        [parsed addObject:packet];
        ni = end;
    }
    if (until) {
        *until = ni;
    }
    return parsed;
}

+ (NSData *)streamFromPacket:(NSData *)packet xorMask:(NSData *)xorMask xorMethod:(int)xorMethod mode:(int)mode
{
    NSMutableData *raw = [[NSMutableData alloc] initWithLength:(PacketStreamHeaderLength + packet.length)];

    uint8_t *ptr = raw.mutableBytes;
    *(uint16_t *)ptr = CFSwapInt16HostToBig(packet.length);
    ptr += PacketStreamHeaderLength;
    [PacketStream memcpyXor:ptr src:packet xorMask:xorMask xorMethod:xorMethod mode:mode];
    
    return raw;
}

+ (NSData *)streamFromPackets:(NSArray<NSData *> *)packets xorMask:(NSData *)xorMask xorMethod:(int)xorMethod mode:(int)mode
{
    NSInteger streamLength = 0;
    for (NSData *p in packets) {
        streamLength += PacketStreamHeaderLength + p.length;
    }

    NSMutableData *raw = [[NSMutableData alloc] initWithLength:streamLength];
    uint8_t *ptr = raw.mutableBytes;
    for (NSData *packet in packets) {
        *(uint16_t *)ptr = CFSwapInt16HostToBig(packet.length);
        ptr += PacketStreamHeaderLength;
        [PacketStream memcpyXor:ptr src:packet xorMask:xorMask xorMethod:xorMethod mode:mode];
        ptr += packet.length;
    }
    return raw;
}

@end
