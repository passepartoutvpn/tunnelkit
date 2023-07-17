//
//  NSRegularExpression+Shortcuts.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 9/9/18.
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

extension NSRegularExpression {
    public convenience init(_ pattern: String) {
        try! self.init(pattern: pattern, options: [])
    }

    public func groups(in string: String) -> [String] {
        var results: [String] = []
        enumerateMatches(in: string, options: [], range: NSRange(location: 0, length: string.count)) { result, _, _ in
            guard let result = result else {
                return
            }
            for i in 0..<numberOfCaptureGroups {
                let subrange = result.range(at: i + 1)
                let match = (string as NSString).substring(with: subrange)
                results.append(match)
            }
        }
        return results
    }
}

extension NSRegularExpression {
    public func enumerateSpacedComponents(in string: String, using block: ([String]) -> Void) {
        enumerateMatches(in: string, options: [], range: NSRange(location: 0, length: string.count)) { result, _, _ in
            guard let range = result?.range else {
                return
            }
            let match = (string as NSString).substring(with: range)
            let tokens = match.components(separatedBy: " ").filter { !$0.isEmpty }
            block(tokens)
        }
    }

    public func enumerateSpacedArguments(in string: String, using block: ([String]) -> Void) {
        enumerateSpacedComponents(in: string) { (tokens) in
            var args = tokens
            args.removeFirst()
            block(args)
        }
    }
}
