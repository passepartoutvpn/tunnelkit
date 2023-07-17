//
//  DataUnit.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 3/30/18.
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

/// Helps expressing integers in bytes, kB, MB, GB.
public enum DataUnit: UInt, CustomStringConvertible {
    case byte = 1

    case kilobyte = 1024

    case megabyte = 1048576

    case gigabyte = 1073741824

    fileprivate var showsDecimals: Bool {
        switch self {
        case .byte, .kilobyte:
            return false

        case .megabyte, .gigabyte:
            return true
        }
    }

    fileprivate var boundary: UInt {
        return UInt(0.1 * Double(rawValue))
    }

    // MARK: CustomStringConvertible

    public var description: String {
        switch self {
        case .byte:
            return "B"

        case .kilobyte:
            return "kB"

        case .megabyte:
            return "MB"

        case .gigabyte:
            return "GB"
        }
    }
}

/// Supports being represented in data unit.
public protocol DataUnitRepresentable {

    /// Returns self expressed in bytes, kB, MB, GB.
    var descriptionAsDataUnit: String { get }
}

extension UInt: DataUnitRepresentable {
    private static let allUnits: [DataUnit] = [
        .gigabyte,
        .megabyte,
        .kilobyte,
        .byte
    ]

    public var descriptionAsDataUnit: String {
        if self == 0 {
            return "0B"
        }
        for u in Self.allUnits {
            if self >= u.boundary {
                if !u.showsDecimals {
                    return "\(self / u.rawValue)\(u)"
                }
                let count = Double(self) / Double(u.rawValue)
                return String(format: "%.2f%@", count, u.description)
            }
        }
        fatalError("Number is negative")
    }
}

extension Int: DataUnitRepresentable {
    public var descriptionAsDataUnit: String {
        return UInt(self).descriptionAsDataUnit
    }
}
