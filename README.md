# TunnelKit

This library provides a simplified Swift/Obj-C implementation of the OpenVPN® protocol for the Apple platforms. The crypto layer is built on top of [OpenSSL][dep-openssl] 1.1.0h, which in turn enables support for a certain range of encryption and digest algorithms.

## Contacts

Twitter: [@keeshux][me-twitter]

Website: [davidederosa.com][me-website]

## Getting started

The client is known to work with [OpenVPN®][openvpn] 2.3+ servers. Key renegotiation and replay protection are also included, but full-fledged configuration files (.ovpn) are not currently supported.

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
    - CA validation
    - Client certificate
- [x] Compression framing
    - Disabled
    - Compress (2.4)
    - LZO (deprecated in 2.4)
- [x] Replay protection (hardcoded window)

The library therefore supports compression framing, just not compression. Remember to match server-side compression framing in order to avoid a confusing loss of data packets. E.g. if server has `comp-lzo no`, client must use `compressionFraming = .compLZO`.

## Installation

### Requirements

- iOS 9.0+ / macOS 10.11+
- Xcode 9+ (Swift 4)
- Git (preinstalled with Xcode Command Line Tools)
- Ruby (preinstalled with macOS)
- [CocoaPods 1.5.0][dep-cocoapods]
- [jazzy][dep-jazzy] (optional, for documentation)

It's highly recommended to use the Git and Ruby packages provided by [Homebrew][dep-brew].

### CocoaPods

To use with CocoaPods just add this to your Podfile:

```ruby
pod 'TunnelKit'
```

### Testing

Download the library codebase locally:

    $ git clone https://github.com/keeshux/TunnelKit.git

Assuming you have a [working CocoaPods environment][dep-cocoapods], setting up the library workspace only requires installing the pod dependencies:

    $ pod install

After that, open `TunnelKit.xcworkspace` in Xcode and run the unit tests found in the `TunnelKitTests` target. A simple CMD+U while on `TunnelKit-iOS` should do that as well.

#### Demo

There is a `Demo` directory containing a simple app for testing the tunnel, called `BasicTunnel`. As usual, prepare for CocoaPods:

    $ pod install

then open `Demo.xcworkspace` and run the `BasicTunnel-iOS` target.

For the VPN to work properly, the `BasicTunnel` demo requires:

- _App Groups_ and _Keychain Sharing_ capabilities
- App IDs with _Packet Tunnel_ entitlements

both in the main app and the tunnel extension target.

In order to test connection to your own server, modify the file `Demo/BasicTunnel-[iOS|macOS]/ViewController.swift` and make sure to set `builder.ca` to the PEM encoded certificate of your VPN server's CA (or `nil` to skip CA validation, however discouraged).

Example:

    builder.endpointProtocols = [TunnelKitProvider.EndpointProtocol(.udp, 1194)]
    builder.ca = """
    -----BEGIN CERTIFICATE-----
    MIIFJDCC...
    -----END CERTIFICATE-----
    """

## Documentation

The library is split into two modules, in order to decouple the low-level protocol implementation from the platform-specific bridging, namely the [NetworkExtension][ne-home] VPN framework.

Full documentation of the public interface is available and can be generated with [jazzy][dep-jazzy]. After installing the jazzy Ruby gem with:

    $ gem install jazzy

enter the root directory of the repository and run:

    $ jazzy

The generated output is stored into the `docs` directory in HTML format.

### Core

Here you will find the low-level entities on top of which the connection is established. Code is mixed Swift and Obj-C, most of it is not exposed to consumers. The *Core* module depends on OpenSSL and is mostly platform-agnostic.

The entry point is the `SessionProxy` class. The networking layer is fully abstract and delegated externally with the use of opaque `IOInterface` (`LinkInterface` and `TunnelInterface`) and `SessionProxyDelegate` protocols.

### AppExtension

The goal of this module is packaging up a black box implementation of a [NEPacketTunnelProvider][ne-ptp], which is the essential part of a Packet Tunnel Provider app extension. You will find the main implementation in the `TunnelKitProvider` class.

Currently, the extension supports VPN over both [UDP][ne-udp] and [TCP][ne-tcp] sockets. A debug log snapshot is optionally maintained and shared to host apps via `UserDefaults` in a shared App Group.

## Contributing

By contributing to this project you are agreeing to the terms stated in the [Contributor License Agreement (CLA)][contrib-cla].

For more details please see [CONTRIBUTING][contrib-readme].

## License

This project is licensed under the [GPLv3 license][license-gpl3], which can be found [here][license-content]. I can provide a different license on request, e.g. if you want to use the library on the App Store. Feel free to contact me in such case.

## Credits

- [PIATunnel][dep-piatunnel-repo] - TunnelKit is a hard fork of PIATunnel that repurposes it substantially. PIATunnel is licensed under the [MIT (Expat) license][license-mit], which can be found [here][dep-piatunnel-license].
- [SwiftyBeaver][dep-swiftybeaver-repo] - A convenient logging library.

This product includes software developed by the OpenSSL Project for use in the OpenSSL Toolkit. ([https://www.openssl.org/][dep-openssl])

© 2002-2018 OpenVPN Inc. - OpenVPN is a registered trademark of OpenVPN Inc.

## Donations

TunnelKit is free software, donations are extremely welcome.

Bitcoin address: [16w2AWamiH2SS68NYSMDcrbh5MnZ1c5eju][me-btc]

[me-twitter]: https://twitter.com/keeshux
[me-website]: https://davidederosa.com
[me-btc]: bitcoin:16w2AWamiH2SS68NYSMDcrbh5MnZ1c5eju

[openvpn]: https://openvpn.net/index.php/open-source/overview.html
[dep-cocoapods]: https://guides.cocoapods.org/using/getting-started.html
[dep-jazzy]: https://github.com/realm/jazzy
[dep-brew]: https://brew.sh/
[dep-openssl]: https://www.openssl.org/

[ne-home]: https://developer.apple.com/documentation/networkextension
[ne-ptp]: https://developer.apple.com/documentation/networkextension/nepackettunnelprovider
[ne-udp]: https://developer.apple.com/documentation/networkextension/nwudpsession
[ne-tcp]: https://developer.apple.com/documentation/networkextension/nwtcpconnection

[license-content]: /LICENSE
[license-gpl3]: https://choosealicense.com/licenses/gpl-3.0/
[license-mit]: https://choosealicense.com/licenses/mit/

[contrib-cla]: /CLA.rst
[contrib-readme]: /CONTRIBUTING.md

[dep-piatunnel-repo]: https://github.com/pia-foss/tunnel-apple
[dep-piatunnel-license]: https://github.com/pia-foss/tunnel-apple/blob/master/LICENSE
[dep-swiftybeaver-repo]: https://github.com/SwiftyBeaver/SwiftyBeaver
