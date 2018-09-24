//
//  TLSBox.m
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

#import <openssl/ssl.h>
#import <openssl/err.h>
#import <openssl/evp.h>

#import "TLSBox.h"
#import "Allocation.h"
#import "Errors.h"

const NSInteger TLSBoxMaxBufferLength = 16384;

NSString *const TLSBoxPeerVerificationErrorNotification = @"TLSBoxPeerVerificationErrorNotification";

static BOOL TLSBoxIsOpenSSLLoaded;

int TLSBoxVerifyPeer(int ok, X509_STORE_CTX *ctx) {
    if (!ok) {
        [[NSNotificationCenter defaultCenter] postNotificationName:TLSBoxPeerVerificationErrorNotification object:nil];
    }
    return ok;
}

@interface TLSBox ()

@property (nonatomic, strong) NSString *caPath;
@property (nonatomic, strong) NSString *clientCertificatePath;
@property (nonatomic, strong) NSString *clientKeyPath;
@property (nonatomic, assign) BOOL isConnected;

@property (nonatomic, unsafe_unretained) SSL_CTX *ctx;
@property (nonatomic, unsafe_unretained) SSL *ssl;
@property (nonatomic, unsafe_unretained) BIO *bioPlainText;
@property (nonatomic, unsafe_unretained) BIO *bioCipherTextIn;
@property (nonatomic, unsafe_unretained) BIO *bioCipherTextOut;

@property (nonatomic, unsafe_unretained) uint8_t *bufferCipherText;

@end

@implementation TLSBox

- (instancetype)init
{
    return [self initWithCAPath:nil clientCertificatePath:nil clientKeyPath:nil];
}

- (instancetype)initWithCAPath:(NSString *)caPath clientCertificatePath:(NSString *)clientCertificatePath clientKeyPath:(NSString *)clientKeyPath
{
    if ((self = [super init])) {
        self.caPath = caPath;
        self.clientCertificatePath = clientCertificatePath;
        self.clientKeyPath = clientKeyPath;
        self.bufferCipherText = allocate_safely(TLSBoxMaxBufferLength);
    }
    return self;
}

- (void)dealloc
{
    if (!self.ctx) {
        return;
    }

    BIO_free_all(self.bioPlainText);
    SSL_free(self.ssl);
    SSL_CTX_free(self.ctx);
    self.isConnected = NO;
    self.ctx = NULL;

    bzero(self.bufferCipherText, TLSBoxMaxBufferLength);
    free(self.bufferCipherText);
}

- (BOOL)startWithError:(NSError *__autoreleasing *)error
{
    if (!TLSBoxIsOpenSSLLoaded) {
        TLSBoxIsOpenSSLLoaded = YES;
    }
    
    self.ctx = SSL_CTX_new(TLS_client_method());
    SSL_CTX_set_options(self.ctx, SSL_OP_NO_SSLv2 | SSL_OP_NO_SSLv3 | SSL_OP_NO_COMPRESSION);
    if (self.caPath) {
        SSL_CTX_set_verify(self.ctx, SSL_VERIFY_PEER, TLSBoxVerifyPeer);
        if (!SSL_CTX_load_verify_locations(self.ctx, [self.caPath cStringUsingEncoding:NSASCIIStringEncoding], NULL)) {
            ERR_print_errors_fp(stdout);
            if (error) {
                *error = TunnelKitErrorWithCode(TunnelKitErrorCodeTLSBoxCA);
            }
            return NO;
        }
    }
    else {
        SSL_CTX_set_verify(self.ctx, SSL_VERIFY_NONE, NULL);
    }
    
    if (self.clientCertificatePath) {
        if (!SSL_CTX_use_certificate_file(self.ctx, [self.clientCertificatePath cStringUsingEncoding:NSASCIIStringEncoding], SSL_FILETYPE_PEM)) {
            ERR_print_errors_fp(stdout);
            if (error) {
                *error = TunnelKitErrorWithCode(TunnelKitErrorCodeTLSBoxClientCertificate);
            }
            return NO;
        }

        if (self.clientKeyPath) {
            if (!SSL_CTX_use_PrivateKey_file(self.ctx, [self.clientKeyPath cStringUsingEncoding:NSASCIIStringEncoding], SSL_FILETYPE_PEM)) {
                ERR_print_errors_fp(stdout);
                if (error) {
                    *error = TunnelKitErrorWithCode(TunnelKitErrorCodeTLSBoxClientKey);
                }
                return NO;
            }
        }
    }

    self.ssl = SSL_new(self.ctx);
    
    self.bioPlainText = BIO_new(BIO_f_ssl());
    self.bioCipherTextIn  = BIO_new(BIO_s_mem());
    self.bioCipherTextOut = BIO_new(BIO_s_mem());
    
    SSL_set_connect_state(self.ssl);
    
    SSL_set_bio(self.ssl, self.bioCipherTextIn, self.bioCipherTextOut);
    BIO_set_ssl(self.bioPlainText, self.ssl, BIO_NOCLOSE);
    
    if (!SSL_do_handshake(self.ssl)) {
        if (error) {
            *error = TunnelKitErrorWithCode(TunnelKitErrorCodeTLSBoxHandshake);
        }
        return NO;
    }
    return YES;
}

#pragma mark Pull

- (NSData *)pullCipherTextWithError:(NSError *__autoreleasing *)error
{
    if (!self.isConnected && !SSL_is_init_finished(self.ssl)) {
        SSL_do_handshake(self.ssl);
    }
    const int ret = BIO_read(self.bioCipherTextOut, self.bufferCipherText, TLSBoxMaxBufferLength);
    if (!self.isConnected && SSL_is_init_finished(self.ssl)) {
        self.isConnected = YES;
    }
    if (ret > 0) {
        return [NSData dataWithBytes:self.bufferCipherText length:ret];
    }
    if ((ret < 0) && !BIO_should_retry(self.bioCipherTextOut)) {
        if (error) {
            *error = TunnelKitErrorWithCode(TunnelKitErrorCodeTLSBoxGeneric);
        }
    }
    return nil;
}

- (BOOL)pullRawPlainText:(uint8_t *)text length:(NSInteger *)length error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(text);
    NSParameterAssert(length);

    const int ret = BIO_read(self.bioPlainText, text, TLSBoxMaxBufferLength);
    if (ret > 0) {
        *length = ret;
        return YES;
    }
    if ((ret < 0) && !BIO_should_retry(self.bioPlainText)) {
        if (error) {
            *error = TunnelKitErrorWithCode(TunnelKitErrorCodeTLSBoxGeneric);
        }
    }
    return NO;
}

#pragma mark Put

- (BOOL)putCipherText:(NSData *)text error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(text);
    
    return [self putRawCipherText:(const uint8_t *)text.bytes length:text.length error:error];
}

- (BOOL)putRawCipherText:(const uint8_t *)text length:(NSInteger)length error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(text);

    const int ret = BIO_write(self.bioCipherTextIn, text, (int)length);
    if (ret != length) {
        if (error) {
            *error = TunnelKitErrorWithCode(TunnelKitErrorCodeTLSBoxGeneric);
        }
        return NO;
    }
    return YES;
}

- (BOOL)putPlainText:(NSString *)text error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(text);

    return [self putRawPlainText:(const uint8_t *)[text cStringUsingEncoding:NSASCIIStringEncoding] length:text.length error:error];
}

- (BOOL)putRawPlainText:(const uint8_t *)text length:(NSInteger)length error:(NSError *__autoreleasing *)error
{
    NSParameterAssert(text);

    const int ret = BIO_write(self.bioPlainText, text, (int)length);
    if (ret != length) {
        if (error) {
            *error = TunnelKitErrorWithCode(TunnelKitErrorCodeTLSBoxGeneric);
        }
        return NO;
    }
    return YES;
}

@end
