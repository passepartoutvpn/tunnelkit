//
//  CryptoCBC.m
//  TunnelKit
//
//  Created by Davide De Rosa on 7/6/18.
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

#import <openssl/evp.h>
#import <openssl/hmac.h>
#import <openssl/rand.h>

#import "CryptoCBC.h"
#import "CryptoMacros.h"
#import "PacketMacros.h"
#import "Allocation.h"
#import "Errors.h"

const NSInteger CryptoCBCMaxHMACLength = 100;

@interface CryptoCBC ()

@property (nonatomic, unsafe_unretained) const EVP_CIPHER *cipher;
@property (nonatomic, unsafe_unretained) const EVP_MD *digest;
@property (nonatomic, assign) int cipherKeyLength;
@property (nonatomic, assign) int cipherIVLength;
@property (nonatomic, assign) int hmacKeyLength;
@property (nonatomic, assign) int digestLength;

@property (nonatomic, unsafe_unretained) EVP_CIPHER_CTX *cipherCtxEnc;
@property (nonatomic, unsafe_unretained) EVP_CIPHER_CTX *cipherCtxDec;
@property (nonatomic, unsafe_unretained) HMAC_CTX *hmacCtxEnc;
@property (nonatomic, unsafe_unretained) HMAC_CTX *hmacCtxDec;
@property (nonatomic, unsafe_unretained) uint8_t *bufferDecHMAC;

@end

@implementation CryptoCBC

- (instancetype)initWithCipherName:(NSString *)cipherName digestName:(NSString *)digestName
{
    NSParameterAssert(!cipherName || [[cipherName uppercaseString] hasSuffix:@"CBC"]);
    NSParameterAssert(digestName);

    self = [super init];
    if (self) {
        if (cipherName) {
            self.cipher = EVP_get_cipherbyname([cipherName cStringUsingEncoding:NSASCIIStringEncoding]);
            NSAssert(self.cipher, @"Unknown cipher '%@'", cipherName);
        }
        self.digest = EVP_get_digestbyname([digestName cStringUsingEncoding:NSASCIIStringEncoding]);
        NSAssert(self.digest, @"Unknown digest '%@'", digestName);

        if (cipherName) {
            self.cipherKeyLength = EVP_CIPHER_key_length(self.cipher);
            self.cipherIVLength = EVP_CIPHER_iv_length(self.cipher);
        }
        // as seen in OpenVPN's crypto_openssl.c:md_kt_size()
        self.hmacKeyLength = EVP_MD_size(self.digest);
        self.digestLength = EVP_MD_size(self.digest);

        if (cipherName) {
            self.cipherCtxEnc = EVP_CIPHER_CTX_new();
            self.cipherCtxDec = EVP_CIPHER_CTX_new();
        }
        self.hmacCtxEnc = HMAC_CTX_new();
        self.hmacCtxDec = HMAC_CTX_new();
        self.bufferDecHMAC = allocate_safely(CryptoCBCMaxHMACLength);
    }
    return self;
}

- (void)dealloc
{
    if (self.cipher) {
        EVP_CIPHER_CTX_free(self.cipherCtxEnc);
        EVP_CIPHER_CTX_free(self.cipherCtxDec);
    }
    HMAC_CTX_free(self.hmacCtxEnc);
    HMAC_CTX_free(self.hmacCtxDec);
    bzero(self.bufferDecHMAC, CryptoCBCMaxHMACLength);
    free(self.bufferDecHMAC);
    
    self.cipher = NULL;
    self.digest = NULL;
}

- (int)extraLength
{
    return 0;
}

- (NSInteger)encryptionCapacityWithLength:(NSInteger)length
{
    return safe_crypto_capacity(length, self.digestLength + self.cipherIVLength);
}

#pragma mark Encrypter

- (void)configureEncryptionWithCipherKey:(ZeroingData *)cipherKey hmacKey:(ZeroingData *)hmacKey
{
    NSParameterAssert(hmacKey);
    NSParameterAssert(hmacKey.count >= self.hmacKeyLength);

    if (self.cipher) {
        NSParameterAssert(cipherKey.count >= self.cipherKeyLength);

        EVP_CIPHER_CTX_reset(self.cipherCtxEnc);
        EVP_CipherInit(self.cipherCtxEnc, self.cipher, cipherKey.bytes, NULL, 1);
    }

    HMAC_CTX_reset(self.hmacCtxEnc);
    HMAC_Init_ex(self.hmacCtxEnc, hmacKey.bytes, self.hmacKeyLength, self.digest, NULL);
}

- (BOOL)encryptBytes:(const uint8_t *)bytes length:(NSInteger)length dest:(uint8_t *)dest destLength:(NSInteger *)destLength extra:(const uint8_t *)extra error:(NSError *__autoreleasing *)error
{
    uint8_t *outIV = dest + self.digestLength;
    uint8_t *outEncrypted = dest + self.digestLength + self.cipherIVLength;
    int l1 = 0, l2 = 0;
    unsigned int l3 = 0;
    int code = 1;

    if (self.cipher) {
        if (RAND_bytes(outIV, self.cipherIVLength) != 1) {
            if (error) {
                *error = TunnelKitErrorWithCode(TunnelKitErrorCodeCryptoBoxRandomGenerator);
            }
            return NO;
        }
        
        TUNNEL_CRYPTO_TRACK_STATUS(code) EVP_CipherInit(self.cipherCtxEnc, NULL, NULL, outIV, -1);
        TUNNEL_CRYPTO_TRACK_STATUS(code) EVP_CipherUpdate(self.cipherCtxEnc, outEncrypted, &l1, bytes, (int)length);
        TUNNEL_CRYPTO_TRACK_STATUS(code) EVP_CipherFinal(self.cipherCtxEnc, outEncrypted + l1, &l2);
    }
    else {
        NSAssert(outEncrypted == outIV, @"cipherIVLength is non-zero");

        memcpy(outEncrypted, bytes, length);
        l1 = (int)length;
    }
    
    TUNNEL_CRYPTO_TRACK_STATUS(code) HMAC_Init_ex(self.hmacCtxEnc, NULL, 0, NULL, NULL);
    TUNNEL_CRYPTO_TRACK_STATUS(code) HMAC_Update(self.hmacCtxEnc, outIV, l1 + l2 + self.cipherIVLength);
    TUNNEL_CRYPTO_TRACK_STATUS(code) HMAC_Final(self.hmacCtxEnc, dest, &l3);
    
    *destLength = l1 + l2 + self.cipherIVLength + self.digestLength;
    
    TUNNEL_CRYPTO_RETURN_STATUS(code)
}

- (id<DataPathEncrypter>)dataPathEncrypter
{
    return [[DataPathCryptoCBC alloc] initWithCrypto:self];
}

#pragma mark Decrypter

- (void)configureDecryptionWithCipherKey:(ZeroingData *)cipherKey hmacKey:(ZeroingData *)hmacKey
{
    NSParameterAssert(hmacKey);
    NSParameterAssert(hmacKey.count >= self.hmacKeyLength);

    if (self.cipher) {
        NSParameterAssert(cipherKey.count >= self.cipherKeyLength);

        EVP_CIPHER_CTX_reset(self.cipherCtxDec);
        EVP_CipherInit(self.cipherCtxDec, self.cipher, cipherKey.bytes, NULL, 0);
    }
    
    HMAC_CTX_reset(self.hmacCtxDec);
    HMAC_Init_ex(self.hmacCtxDec, hmacKey.bytes, self.hmacKeyLength, self.digest, NULL);
}

- (BOOL)decryptBytes:(const uint8_t *)bytes length:(NSInteger)length dest:(uint8_t *)dest destLength:(NSInteger *)destLength extra:(const uint8_t *)extra error:(NSError *__autoreleasing *)error
{
    NSAssert(self.cipher, @"No cipher provided");

    const uint8_t *iv = bytes + self.digestLength;
    const uint8_t *encrypted = bytes + self.digestLength + self.cipherIVLength;
    int l1 = 0, l2 = 0;
    int code = 1;
    
    TUNNEL_CRYPTO_TRACK_STATUS(code) HMAC_Init_ex(self.hmacCtxDec, NULL, 0, NULL, NULL);
    TUNNEL_CRYPTO_TRACK_STATUS(code) HMAC_Update(self.hmacCtxDec, bytes + self.digestLength, length - self.digestLength);
    TUNNEL_CRYPTO_TRACK_STATUS(code) HMAC_Final(self.hmacCtxDec, self.bufferDecHMAC, (unsigned *)&l1);
    
    if (TUNNEL_CRYPTO_SUCCESS(code) && CRYPTO_memcmp(self.bufferDecHMAC, bytes, self.digestLength) != 0) {
        if (error) {
            *error = TunnelKitErrorWithCode(TunnelKitErrorCodeCryptoBoxHMAC);
        }
        return NO;
    }
    
    TUNNEL_CRYPTO_TRACK_STATUS(code) EVP_CipherInit(self.cipherCtxDec, NULL, NULL, iv, -1);
    TUNNEL_CRYPTO_TRACK_STATUS(code) EVP_CipherUpdate(self.cipherCtxDec, dest, &l1, encrypted, (int)length - self.digestLength - self.cipherIVLength);
    TUNNEL_CRYPTO_TRACK_STATUS(code) EVP_CipherFinal(self.cipherCtxDec, dest + l1, &l2);

    *destLength = l1 + l2;

    TUNNEL_CRYPTO_RETURN_STATUS(code)
}

- (BOOL)verifyBytes:(const uint8_t *)bytes length:(NSInteger)length extra:(const uint8_t *)extra error:(NSError *__autoreleasing *)error
{
    int l1 = 0;
    int code = 1;
    
    TUNNEL_CRYPTO_TRACK_STATUS(code) HMAC_Init_ex(self.hmacCtxDec, NULL, 0, NULL, NULL);
    TUNNEL_CRYPTO_TRACK_STATUS(code) HMAC_Update(self.hmacCtxDec, bytes + self.digestLength, length - self.digestLength);
    TUNNEL_CRYPTO_TRACK_STATUS(code) HMAC_Final(self.hmacCtxDec, self.bufferDecHMAC, (unsigned *)&l1);
    
    if (TUNNEL_CRYPTO_SUCCESS(code) && CRYPTO_memcmp(self.bufferDecHMAC, bytes, self.digestLength) != 0) {
        if (error) {
            *error = TunnelKitErrorWithCode(TunnelKitErrorCodeCryptoBoxHMAC);
        }
        return NO;
    }

    TUNNEL_CRYPTO_RETURN_STATUS(code)
}

- (id<DataPathDecrypter>)dataPathDecrypter
{
    return [[DataPathCryptoCBC alloc] initWithCrypto:self];
}

@end

#pragma mark -

@interface DataPathCryptoCBC ()

@property (nonatomic, strong) CryptoCBC *crypto;
@property (nonatomic, assign) int headerLength;
@property (nonatomic, copy) void (^setDataHeader)(uint8_t *, uint8_t);
@property (nonatomic, copy) BOOL (^checkPeerId)(const uint8_t *);

@end

@implementation DataPathCryptoCBC

- (instancetype)initWithCrypto:(CryptoCBC *)crypto
{
    if ((self = [super init])) {
        self.crypto = crypto;
        self.peerId = PacketPeerIdDisabled;
    }
    return self;
}

#pragma mark DataPathChannel

- (void)setPeerId:(uint32_t)peerId
{
    peerId &= 0xffffff;

    if (peerId == PacketPeerIdDisabled) {
        self.headerLength = PacketOpcodeLength;
        self.setDataHeader = ^(uint8_t *to, uint8_t key) {
            PacketHeaderSet(to, PacketCodeDataV1, key, nil);
        };
        self.checkPeerId = NULL;
    }
    else {
        self.headerLength = PacketOpcodeLength + PacketPeerIdLength;
        self.setDataHeader = ^(uint8_t *to, uint8_t key) {
            PacketHeaderSetDataV2(to, key, peerId);
        };
        self.checkPeerId = ^BOOL(const uint8_t *ptr) {
            return (PacketHeaderGetDataV2PeerId(ptr) == peerId);
        };
    }
}

- (NSInteger)encryptionCapacityWithLength:(NSInteger)length
{
    return [self.crypto encryptionCapacityWithLength:length];
}

#pragma mark DataPathEncrypter

- (void)assembleDataPacketWithBlock:(DataPathAssembleBlock)block packetId:(uint32_t)packetId payload:(NSData *)payload into:(uint8_t *)packetBytes length:(NSInteger *)packetLength
{
    uint8_t *ptr = packetBytes;
    *(uint32_t *)ptr = htonl(packetId);
    ptr += sizeof(uint32_t);
    *packetLength = (int)(ptr - packetBytes + payload.length);
    if (!block) {
        memcpy(ptr, payload.bytes, payload.length);
        return;
    }

    NSInteger packetLengthOffset;
    block(ptr, &packetLengthOffset, payload);
    *packetLength += packetLengthOffset;
}

- (NSData *)encryptedDataPacketWithKey:(uint8_t)key packetId:(uint32_t)packetId packetBytes:(const uint8_t *)packetBytes packetLength:(NSInteger)packetLength error:(NSError *__autoreleasing *)error
{
    const int capacity = self.headerLength + (int)[self.crypto encryptionCapacityWithLength:packetLength];
    NSMutableData *encryptedPacket = [[NSMutableData alloc] initWithLength:capacity];
    uint8_t *ptr = encryptedPacket.mutableBytes;
    NSInteger encryptedPacketLength = INT_MAX;
    const BOOL success = [self.crypto encryptBytes:packetBytes
                                            length:packetLength
                                              dest:(ptr + self.headerLength) // skip header byte
                                        destLength:&encryptedPacketLength
                                             extra:NULL
                                             error:error];
    
    NSAssert(encryptedPacketLength <= capacity, @"Did not allocate enough bytes for payload");
    
    if (!success) {
        return nil;
    }

    self.setDataHeader(ptr, key);
    encryptedPacket.length = self.headerLength + encryptedPacketLength;
    return encryptedPacket;
}

#pragma mark DataPathDecrypter

- (BOOL)decryptDataPacket:(NSData *)packet into:(uint8_t *)packetBytes length:(NSInteger *)packetLength packetId:(uint32_t *)packetId error:(NSError *__autoreleasing *)error
{
    // skip header = (code, key)
    const BOOL success = [self.crypto decryptBytes:(packet.bytes + self.headerLength)
                                            length:(int)(packet.length - self.headerLength)
                                              dest:packetBytes
                                        destLength:packetLength
                                             extra:NULL
                                             error:error];
    if (!success) {
        return NO;
    }
    if (self.checkPeerId && !self.checkPeerId(packet.bytes)) {
        if (error) {
            *error = TunnelKitErrorWithCode(TunnelKitErrorCodeDataPathPeerIdMismatch);
        }
        return NO;
    }
    *packetId = ntohl(*(uint32_t *)packetBytes);
    return YES;
}

- (const uint8_t *)parsePayloadWithBlock:(DataPathParseBlock)block length:(NSInteger *)length packetBytes:(uint8_t *)packetBytes packetLength:(NSInteger)packetLength
{
    uint8_t *payload = packetBytes;
    payload += sizeof(uint32_t); // packet id
    *length = packetLength - (int)(payload - packetBytes);
    if (!block) {
        return payload;
    }

    NSInteger payloadOffset;
    NSInteger payloadHeaderLength;
    block(payload, &payloadOffset, &payloadHeaderLength, packetBytes, packetLength);
    *length -= payloadHeaderLength;
    return payload + payloadOffset;
}

@end
