import SwiftyBeaver

private let log = SwiftyBeaver.self

extension OSLogType {
    var sbLevel: SwiftyBeaver.Level {
        switch self {
        case .debug:
            return .debug

        case .info:
            return .info

        case .error, .fault:
            return .error

        default:
            return .info
        }
    }
}

// SPDX-License-Identifier: MIT
// Copyright © 2018-2021 WireGuard LLC. All Rights Reserved.

import Foundation
import os.log

public func wg_log(_ type: OSLogType, staticMessage msg: StaticString) {
    os_log(msg, log: OSLog.default, type: type)
    log.custom(level: type.sbLevel, message: msg, context: nil)
}

public func wg_log(_ type: OSLogType, message msg: String) {
    os_log("%{public}s", log: OSLog.default, type: type, msg)
    log.custom(level: type.sbLevel, message: msg, context: nil)
}
