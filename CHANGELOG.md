
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project _will soonly adhere_ to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Client certificate verification. [#3](https://github.com/keeshux/tunnelkit/pull/3)
- Support for both `--comp-lzo` and `--compress` compression framing. [#2](https://github.com/keeshux/tunnelkit/pull/2), [#5](https://github.com/keeshux/tunnelkit/pull/5), [#10](https://github.com/keeshux/tunnelkit/pull/10)
- Routes setup from PUSH_REPLY. [#7](https://github.com/keeshux/tunnelkit/pull/7)
- Support for IPv6. [#8](https://github.com/keeshux/tunnelkit/pull/8)
- Support for server-side NCP. [#11](https://github.com/keeshux/tunnelkit/pull/11)
- Property to mark ciphers not requiring digest auth (e.g. GCM). [#13](https://github.com/keeshux/tunnelkit/pull/13)
- `Codable` implementations for native Swift serialization. [#15](https://github.com/keeshux/tunnelkit/pull/15)
- More cipher and digest algorithms. [#16](https://github.com/keeshux/tunnelkit/pull/16)
- Negotiated compression framing from PUSH_REPLY. [#19](https://github.com/keeshux/tunnelkit/pull/19)
- Customizable keep-alive. [#20](https://github.com/keeshux/tunnelkit/pull/20)
- Negotiated keep-alive from PUSH_REPLY. [#22](https://github.com/keeshux/tunnelkit/pull/22)
- Peer-info metadata.

### Changed

- Deep refactoring of control channel for future extensibility.
- App group moved out of tunnel configuration, to make it more platform-agnostic and coherent to serialize.
- Minor adjustments for Xcode 10 / Swift 4.2.
- Several internal renamings.

### Fixed

- Sensitive data logged in PUSH_REPLY. [#12](https://github.com/keeshux/tunnelkit/pull/12)
- Bad interpretation of 0 seconds between renegotiations. [#18](https://github.com/keeshux/tunnelkit/pull/18)
- Incorrect behavior on data-related failures. [#21](https://github.com/keeshux/tunnelkit/pull/21)

## 1.0.0 (2018-08-23)

### Added

- Initial fork from https://github.com/pia-foss/tunnel-apple

### Removed

- Non-standard PIA patches.
