![iOS 13+](https://img.shields.io/badge/ios-13+-green.svg)
![macOS 10.15+](https://img.shields.io/badge/macos-10.15+-green.svg)
[![License GPLv3](https://img.shields.io/badge/license-GPLv3-lightgray.svg)](LICENSE)

[![Unit Tests](https://github.com/passepartoutvpn/tunnelkit/actions/workflows/test.yml/badge.svg)](https://github.com/passepartoutvpn/tunnelkit/actions/workflows/test.yml)
[![Release](https://github.com/passepartoutvpn/tunnelkit/actions/workflows/release.yml/badge.svg)](https://github.com/passepartoutvpn/tunnelkit/actions/workflows/release.yml)

# TunnelKit

This library provides a generic framework for VPN development on Apple platforms.

## OpenVPN

TunnelKit comes with a simplified Swift/Obj-C implementation of the [OpenVPN®][dep-openvpn] protocol, whose crypto layer is built on top of [OpenSSL 1.1.1][dep-openssl].

The client is known to work with OpenVPN® 2.3+ servers.

- [x] Handshake and tunneling over UDP or TCP
- [x] Ciphers
    - AES-CBC (128/192/256 bit)
    - AES-GCM (128/192/256 bit, 2.4)
- [x] HMAC digests
    - SHA-1
    - SHA-2 (224/256/384/512 bit)
- [x] NCP (Negotiable Crypto Parameters, 2.4)
    - Server-side
- [x] TLS handshake
    - Server validation (CA, EKU)
    - Client certificate
- [x] TLS wrapping
    - Authentication (`--tls-auth`)
    - Encryption (`--tls-crypt`)
- [x] Compression framing
    - Via `--comp-lzo` (deprecated in 2.4)
    - Via `--compress`
- [x] Compression algorithms
    - LZO (via `--comp-lzo` or `--compress lzo`)
- [x] Key renegotiation
- [x] Replay protection (hardcoded window)

The library therefore supports compression framing, just not newer compression. Remember to match server-side compression and framing, otherwise the client will shut down with an error. E.g. if server has `comp-lzo no`, client must use `compressionFraming = .compLZO`.

### Support for .ovpn configuration

TunnelKit can parse .ovpn configuration files. Below are a few details worth mentioning.

#### Non-standard

- XOR-patch functionality:
    - Multi-byte XOR Masking
        - Via `--scramble xormask <passphrase>`
        - XOR all incoming and outgoing bytes by the passphrase given
    - XOR Position Masking
        - Via `--scramble xorptrpos`
        - XOR all bytes by their position in the array
    - Packet Reverse Scramble
        - Via `--scramble reverse`
        - Keeps the first byte and reverses the rest of the array
    - XOR Scramble Obfuscate
        - Via `--scramble obfuscate <passphrase>`
        - Performs a combination of the three above (specifically `xormask <passphrase>` -> `xorptrpos` -> `reverse` -> `xorptrpos` for reading, and the opposite for writing) 
    - See [Tunnelblick website][about-tunnelblick-xor] for more details (Patch was written in accordance with Tunnelblick's patch for compatibility)

#### Unsupported

- UDP fragmentation, i.e. `--fragment`
- Compression via `--compress` other than empty or `lzo`
- Connecting via proxy
- External file references (inline `<block>` only)
- Static key encryption (non-TLS)
- `<connection>` blocks
- `net_gateway` literals in routes

#### Ignored

- Some MTU overrides
    - `--link-mtu` and variants
    - `--mssfix`
- Multiple `--remote` with different `host` values (first wins)
- Static client-side routes

Many other flags are ignored too but it's normally not an issue.

## WireGuard

TunnelKit offers a user-friendly API to the modern [WireGuard®][dep-wireguard] protocol.

### Manual Xcode steps

If you add any `TunnelKitWireGuard*` Swift package to the "Link with binary libraries" section of your app or tunnel extension, you are bound to hit this error:

```
ld: library not found for -lwg-go
```

because part of the WireGuardKit package is based on `make`, which SwiftPM doesn't support yet.

Therefore, make sure to follow the steps below for proper integration:

- Copy `Scripts/build_wireguard_go_bridge.sh` somewhere in your project.
- In Xcode, click File -> New -> Target. Switch to "Other" tab and choose "External Build System".
- Type a name for your target.
- Open the "Info" tab and replace `/usr/bin/make` with `$(PROJECT_DIR)/path/to/build_wireguard_go_bridge.sh` in "Build Tool".
- Switch to "Build Settings" and find SDKROOT. Type in `macosx` if you target macOS, or type in `iphoneos` if you target iOS.
- Locate your tunnel extension target and switch to "Build Phases" tab.
- Locate "Dependencies" section and hit "+" to add the target you have just created.
- Repeat the process for each platform.

## Installation

### Requirements

- iOS 13.0+ / macOS 10.15+
- SwiftPM 5.3
- Git (preinstalled with Xcode Command Line Tools)
- golang (for WireGuardKit)

It's highly recommended to use the Git package provided by [Homebrew][dep-brew].

### Caveats

Make sure to set "Enable Bitcode" (iOS) to NO, otherwise the library [would not be able to link OpenSSL][about-pr-bitcode] (OpenVPN) and the `wg-go` bridge (WireGuard).

Recent versions of Xcode (latest is 13.1) have an issue where the "Frameworks" directory is replicated inside application extensions. This is not a blocker during development, but will prevent your archive from being validated against App Store Connect due to the following error:

    ERROR ITMS-90206: "Invalid Bundle. The bundle at '*.appex' contains disallowed file 'Frameworks'."

You will need to add a "Run Script" phase to your main app target where you manually remove the offending folder, i.e.:

    rm -rf "${BUILT_PRODUCTS_DIR}/${PLUGINS_FOLDER_PATH}/YourTunnelTarget.appex/Frameworks"

for iOS and:

    rm -rf "${BUILT_PRODUCTS_DIR}/${PLUGINS_FOLDER_PATH}/YourTunnelTarget.appex/Contents/Frameworks"

for macOS.

### Demo

Download the library codebase locally:

    $ git clone https://github.com/passepartoutvpn/tunnelkit.git

There are demo targets containing a simple app for testing the tunnels. Open `Demo/TunnelKit.xcodeproject` in Xcode and run it on both iOS and macOS.

For the VPN to work properly, the demo requires:

- _App Groups_ and _Keychain Sharing_ capabilities
- App IDs with _Packet Tunnel_ entitlements

both in the main app and the tunnel extension targets.

In order to test connectivity in your own environment, modify the file `Demo/Demo/Configuration.swift` to match your VPN server parameters.

Example:

    private let ca = CryptoContainer(pem: """
	-----BEGIN CERTIFICATE-----
	MIIFJDCC...
	-----END CERTIFICATE-----
    """)

Make sure to also update the following constants in the `*ViewController.swift` files, according to your developer account and your target bundle identifiers:

    private let appGroup = "..."
    private let tunnelIdentifier = "..."

Remember that the App Group on macOS requires a team ID prefix.

## Documentation

The library is split into several modules, in order to decouple the low-level protocol implementation from the platform-specific bridging, namely the [NetworkExtension][ne-home] VPN framework.

Full documentation of the public interface is available and can be generated by opening the package in Xcode and running "Build Documentation" (Xcode 13).

### TunnelKit

This component includes convenient classes to control the VPN tunnel from your app without the NetworkExtension headaches. Have a look at `VPN` implementations:

- `MockVPN` (default, useful to test on simulator)
- `NetworkExtensionVPN` (anything based on NetworkExtension)

### TunnelKitOpenVPN

Provides the entities to interact with the OpenVPN tunnel.

### TunnelKitOpenVPNAppExtension

Contains the `NEPacketTunnelProvider` implementation of a OpenVPN tunnel.

### TunnelKitWireGuard

Provides the entities to interact with the WireGuard tunnel.

### TunnelKitWireGuardAppExtension

Contains the `NEPacketTunnelProvider` implementation of a WireGuard tunnel.

## License

Copyright (c) 2022 Davide De Rosa. All rights reserved.

### Part I

This project is licensed under the [GPLv3][license-content].

### Part II

As seen in [libsignal-protocol-c][license-signal]:

> Additional Permissions For Submission to Apple App Store: Provided that you are otherwise in compliance with the GPLv3 for each covered work you convey (including without limitation making the Corresponding Source available in compliance with Section 6 of the GPLv3), the Author also grants you the additional permission to convey through the Apple App Store non-source executable versions of the Program as incorporated into each applicable covered work as Executable Versions only under the Mozilla Public License version 2.0 (https://www.mozilla.org/en-US/MPL/2.0/).

### Part III

Part I and II do not apply to the LZO library, which remains licensed under the terms of the GPLv2+.

### Contributing

By contributing to this project you are agreeing to the terms stated in the [Contributor License Agreement (CLA)][contrib-cla].

For more details please see [CONTRIBUTING][contrib-readme].

### Other licenses

A custom TunnelKit license, e.g. for use in proprietary software, may be negotiated [on request][license-contact].

## Credits

- [lzo][dep-lzo-website] - Copyright (c) 1996-2017 Markus F.X.J. Oberhumer
- [PIATunnel][dep-piatunnel-repo] - Copyright (c) 2018-Present Private Internet Access
- [SURFnet][ppl-surfnet]
- [SwiftyBeaver][dep-swiftybeaver-repo] - Copyright (c) 2015 Sebastian Kreutzberger
- [XMB5][ppl-xmb5] for the [XOR patch][ppl-xmb5-xor] - Copyright (c) 2020 Sam Foxman
- [tmthecoder][ppl-tmthecoder] for the complete [XOR patch][ppl-tmthecoder-xor] - Copyright (c) 2022 Tejas Mehta
- [eduVPN][ppl-eduvpn] for the convenient WireGuardKitGo script

### OpenVPN

© Copyright 2022 OpenVPN | OpenVPN is a registered trademark of OpenVPN, Inc.

### WireGuard

© Copyright 2015-2022 Jason A. Donenfeld. All Rights Reserved. "WireGuard" and the "WireGuard" logo are registered trademarks of Jason A. Donenfeld.

### OpenSSL

This product includes software developed by the OpenSSL Project for use in the OpenSSL Toolkit. ([https://www.openssl.org/][dep-openssl])

## Contacts

Twitter: [@keeshux][about-twitter]

Website: [passepartoutvpn.app][about-website]

[dep-brew]: https://brew.sh/
[dep-openvpn]: https://openvpn.net/index.php/open-source/overview.html
[dep-wireguard]: https://www.wireguard.com/
[dep-openssl]: https://www.openssl.org/

[ne-home]: https://developer.apple.com/documentation/networkextension
[ne-ptp]: https://developer.apple.com/documentation/networkextension/nepackettunnelprovider
[ne-udp]: https://developer.apple.com/documentation/networkextension/nwudpsession
[ne-tcp]: https://developer.apple.com/documentation/networkextension/nwtcpconnection

[license-content]: LICENSE
[license-signal]: https://github.com/signalapp/libsignal-protocol-c#license
[license-mit]: https://choosealicense.com/licenses/mit/
[license-contact]: mailto:license@passepartoutvpn.app
[contrib-cla]: CLA.rst
[contrib-readme]: CONTRIBUTING.md

[dep-piatunnel-repo]: https://github.com/pia-foss/tunnel-apple
[dep-swiftybeaver-repo]: https://github.com/SwiftyBeaver/SwiftyBeaver
[dep-lzo-website]: http://www.oberhumer.com/opensource/lzo/
[ppl-surfnet]: https://www.surf.nl/en/about-surf/subsidiaries/surfnet
[ppl-xmb5]: https://github.com/XMB5
[ppl-xmb5-xor]: https://github.com/passepartoutvpn/tunnelkit/pull/170
[ppl-tmthecoder]: https://github.com/tmthecoder
[ppl-tmthecoder-xor]: https://github.com/passepartoutvpn/tunnelkit/pull/255
[ppl-eduvpn]: https://github.com/eduvpn/apple
[about-tunnelblick-xor]: https://tunnelblick.net/cOpenvpn_xorpatch.html
[about-pr-bitcode]: https://github.com/passepartoutvpn/tunnelkit/issues/51

[about-twitter]: https://twitter.com/keeshux
[about-website]: https://passepartoutvpn.app
