import Foundation
import Darwin

/// Removes URL userinfo, query and fragment data without discarding endpoint context.
internal enum ReportSanitizer {
    private struct Start {
        let lower: Int
        let upper: Int
        let authority: Bool
    }

    internal static func sanitizeUrls(_ text: String, droppingIncompleteUrl: Bool = false) -> String {
        sanitize(text, inputLimit: nil, dropLast: droppingIncompleteUrl)
    }

    internal static func sanitizeValues(_ values: [String: String]) -> [String: String] {
        values.mapValues { sanitizeUrls($0) }
    }

    internal static func sanitizeText(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let clean = sanitize(text, inputLimit: limit <= Int.max / 10 ? limit * 10 : Int.max)
        guard clean.count > limit else { return clean }
        guard limit > 3 else { return String(clean.prefix(limit)) }
        // A final output cut must not leave a partial URL authority either.
        let boundarySafe = sanitize(clean, inputLimit: limit - 3)
        return String(boundarySafe.prefix(limit - 3)) + "..."
    }

    private static func sanitize(_ source: String, inputLimit: Int?, dropLast: Bool = false) -> String {
        let text = normalizeEncodedUrls(redactAuthorization(source))
        let bytes = Array(text.utf8)
        let bound = inputLimit.map { limit -> Int in
            let end = text.index(text.startIndex, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex
            return text.utf8.distance(from: text.utf8.startIndex, to: end)
        }
        var result = [UInt8]()
        var cursor = 0
        while let start = nextStart(bytes, from: cursor, to: bytes.count, relative: true) {
            result.append(contentsOf: bytes[cursor..<start.lower])
            var end = tokenEnd(bytes, from: start.upper)
            var tail = start
            while let nested = nextNestedStart(bytes, start: tail, to: end, relative: true) { tail = nested }
            let authorityEnd = tail.authority ? firstBoundary(bytes, from: tail.upper, to: end) : tail.upper
            let authority = decodedAuthority(bytes[tail.upper..<authorityEnd])
            // R5: one following whitespace/quote-delimited fragment may complete
            // malformed userinfo. Never consume a separate, complete URL.
            if tail.authority, authorityEnd == end, end < bytes.count,
               authority.contains(58), !authority.contains(64), !isIPv6(bytes[tail.upper..<authorityEnd]) {
                var continuation = end
                while continuation < bytes.count, isDelimiter(bytes, at: continuation) {
                    continuation += bytes[continuation] < 128 ? 1 : (bytes[continuation] < 0xE0 ? 2 : 3)
                }
                let continuationEnd = tokenEnd(bytes, from: continuation)
                if nextStart(bytes, from: continuation, to: continuationEnd, relative: true, opaque: false) == nil,
                   let at = bytes[continuation..<continuationEnd].lastIndex(of: 64) {
                    end = continuationEnd
                    if !crossesBound(start.lower, end, bound), !(dropLast && end == bytes.count) {
                        if tail.lower > start.lower {
                            result.append(contentsOf: stripToken(bytes, start: start, end: tail.lower))
                        }
                        // A nested URL inside a query must not promote query data
                        // back into the report after that query has been removed.
                        if !bytes[start.lower..<tail.lower].contains(where: { $0 == 63 || $0 == 35 }) {
                            result.append(contentsOf: bytes[tail.lower..<tail.upper])
                            result.append(contentsOf: "[redacted]".utf8)
                            let suffix = Array(bytes[(at + 1)..<end])
                            let synthetic = Array(bytes[tail.lower..<tail.upper]) + suffix
                            let clean = stripToken(synthetic, start: Start(lower: 0, upper: tail.upper - tail.lower, authority: true), end: synthetic.count)
                            result.append(contentsOf: clean.dropFirst(tail.upper - tail.lower))
                        }
                    }
                    cursor = end
                    continue
                }
            }
            if !crossesBound(start.lower, end, bound), !(dropLast && end == bytes.count) {
                result.append(contentsOf: stripToken(bytes, start: start, end: end))
            }
            cursor = end
        }
        result.append(contentsOf: bytes[cursor...])
        return String(decoding: result, as: UTF8.self)
    }

    // Header values can also arrive in exception text, stack traces and tags.
    // The whole line is a header value, regardless of authentication scheme.
    // Keep line separators so diagnostics on following lines survive.
    private static let authorization = try! NSRegularExpression(
        pattern: #"(?i)\b((?:proxy-|x-)?authorization)[ \t]*[:=][^\r\n\u0085\u2028\u2029]*"#)

    private static func redactAuthorization(_ text: String) -> String {
        authorization.stringByReplacingMatches(in: text,
            range: NSRange(text.startIndex..., in: text), withTemplate: "$1: [redacted]")
    }

    private static func crossesBound(_ start: Int, _ end: Int, _ bound: Int?) -> Bool {
        guard let bound else { return false }
        return start < bound && bound < end
    }

    private static func stripToken(_ bytes: [UInt8], start initial: Start, end: Int) -> [UInt8] {
        var result = [UInt8]()
        var start = initial
        let lastAt = bytes[initial.upper..<end].lastIndex(of: 64)
        while true {
            // A double slash within a path is path data. Nested explicit schemes
            // still start a new authority, including ftp/ws/wss and custom schemes.
            let next = nextNestedStart(bytes, start: start, to: end, relative: false, lastAt: lastAt)
            let segmentEnd = next?.lower ?? end
            let authorityEnd = start.authority ? firstBoundary(bytes, from: start.upper, to: segmentEnd) : start.upper
            let authority = decodedAuthority(bytes[start.upper..<authorityEnd])
            let at = authority.lastIndex(of: 64)
            if start.authority, at == nil, !isIPv6(bytes[start.upper..<authorityEnd]),
               hasCredentialPort(authority) || (authority.contains(58) && (lastAt ?? -1) >= authorityEnd) {
                // R4a: numeric ports and numeric passwords cannot be distinguished.
                result.append(contentsOf: bytes[start.lower..<start.upper])
                result.append(contentsOf: "[redacted]".utf8)
                return result
            }
            result.append(contentsOf: bytes[start.lower..<start.upper])
            if let at {
                result.append(contentsOf: authority[(at + 1)...])
            } else {
                result.append(contentsOf: bytes[start.upper..<authorityEnd])
            }
            var pathEnd = authorityEnd
            while pathEnd < segmentEnd, bytes[pathEnd] != 63, bytes[pathEnd] != 35 { pathEnd += 1 }
            result.append(contentsOf: bytes[authorityEnd..<pathEnd])
            // Query and fragment consume the entire remaining token. Commas and
            // embedded schemes cannot turn query data back into public text.
            if pathEnd < segmentEnd { return result }
            guard let next else { return result }
            start = next
        }
    }

    private static func firstBoundary(_ bytes: [UInt8], from: Int, to: Int) -> Int {
        var index = from
        while index < to, bytes[index] != 47, bytes[index] != 63, bytes[index] != 35 { index += 1 }
        return index
    }

    private static func tokenEnd(_ bytes: [UInt8], from: Int) -> Int {
        var index = from
        while index < bytes.count, !isDelimiter(bytes, at: index) { index += 1 }
        return index
    }

    private static func isDelimiter(_ bytes: [UInt8], at index: Int) -> Bool {
        let byte = bytes[index]
        if byte <= 32 || byte == 34 || byte == 39 || byte == 60 || byte == 62 { return true }
        // Unicode whitespace is a boundary too; never split a UTF-8 code point.
        if byte == 0xC2, index + 1 < bytes.count { return bytes[index + 1] == 0x85 || bytes[index + 1] == 0xA0 }
        if byte == 0xE1, index + 2 < bytes.count { return bytes[index + 1] == 0x9A && bytes[index + 2] == 0x80 }
        if byte == 0xE2, index + 2 < bytes.count {
            return bytes[index + 1] == 0x80 && (0x80...0x8A).contains(bytes[index + 2])
                || bytes[index + 1] == 0x80 && (0xA8...0xA9).contains(bytes[index + 2])
                || bytes[index + 1] == 0x80 && bytes[index + 2] == 0xAF
                || bytes[index + 1] == 0x81 && bytes[index + 2] == 0x9F
        }
        return byte == 0xE3 && index + 2 < bytes.count && bytes[index + 1] == 0x80 && bytes[index + 2] == 0x80
    }

    private static func letter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) }
    private static func schemeCharacter(_ byte: UInt8) -> Bool {
        letter(byte) || (48...57).contains(byte) || byte == 43 || byte == 45 || byte == 46
    }

    /// A colon in an authority can be userinfo, while a colon after its
    /// path boundary can introduce an opaque wrapper around another URL.
    private static func nextNestedStart(_ bytes: [UInt8], start: Start, to: Int,
                                        relative: Bool, lastAt: Int? = nil) -> Start? {
        let candidate = nextStart(bytes, from: start.upper, to: to, relative: relative,
                                  opaque: false, lastAt: lastAt, afterColon: !start.authority)
        guard start.authority else { return candidate }
        let path = firstBoundary(bytes, from: start.upper, to: to)
        let nested = nextStart(bytes, from: path, to: to, relative: relative,
                               opaque: false, lastAt: lastAt, afterColon: true)
        if let candidate, let nested { return candidate.lower <= nested.lower ? candidate : nested }
        return candidate ?? nested
    }

    /// Each character run is visited once, rather than searching every suffix
    /// for every scheme. This also preserves unrelated double-slash text.
    private static func nextStart(_ bytes: [UInt8], from: Int, to: Int, relative: Bool, opaque: Bool = true, lastAt: Int? = nil, afterColon: Bool = false) -> Start? {
        var index = from
        while index < to {
            if letter(bytes[index]) {
                let lower = index
                index += 1
                while index < to, schemeCharacter(bytes[index]) { index += 1 }
                if index < to, bytes[index] == 58 {
                    if index + 2 < to, bytes[index + 1] == 47, bytes[index + 2] == 47,
                       (opaque || afterColon || lower == 0 || bytes[lower - 1] != 58) {
                        return Start(lower: lower, upper: index + 3, authority: true)
                    }
                    if opaque { return Start(lower: lower, upper: index + 1, authority: false) }
                }
            } else if bytes[index] == 47, index + 2 < to, bytes[index + 1] == 47,
                      bytes[index + 2] != 47, !isDelimiter(bytes, at: index + 2),
                      (index == 0 || bytes[index - 1] != 47 && bytes[index - 1] != 58) {
                if relative { return Start(lower: index, upper: index + 2, authority: true) }
                // Within a path, recognize a relative authority only when it
                // carries userinfo or has R4a's ambiguous colon/at-sign shape.
                let end = firstBoundary(bytes, from: index + 2, to: to)
                let authority = decodedAuthority(bytes[(index + 2)..<end])
                if authority.contains(64) || (authority.contains(58) && !isIPv6(bytes[(index + 2)..<end]) && (lastAt ?? -1) >= end) {
                    return Start(lower: index, upper: index + 2, authority: true)
                }
                index += 2
            } else { index += 1 }
        }
        return nil
    }

    private static func decodedAuthority(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        guard bytes.contains(37) else { return Array(bytes) }
        let text = String(decoding: bytes, as: UTF8.self)
        return Array((text.removingPercentEncoding ?? decodeStructuralEscapes(text)).utf8)
    }

    private static func hasCredentialPort(_ authority: [UInt8]) -> Bool {
        // Error descriptions often put punctuation directly after host:port.
        // Ignore that punctuation, while preserving an actually empty port.
        let endpoint = authority.reversed().drop(while: { ",.;:!)]}".utf8.contains($0) }).reversed()
        guard let colon = endpoint.lastIndex(of: 58) else { return false }
        let port = endpoint[endpoint.index(after: colon)...]
        return !port.isEmpty && !port.allSatisfy { (48...57).contains($0) }
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
    }

    private static func isIPv6(_ authority: ArraySlice<UInt8>) -> Bool {
        guard authority.first == 91, let end = authority.firstIndex(of: 93) else { return false }
        let suffix = authority[(end + 1)...]
        guard suffix.isEmpty || suffix.first == 58 && suffix.count > 1 && suffix.dropFirst().allSatisfy({ (48...57).contains($0) }) else { return false }
        let literal = authority[(authority.startIndex + 1)..<end]
        let address: ArraySlice<UInt8>
        if let percent = literal.firstIndex(of: 37) {
            var zone = literal[(percent + 1)...]
            // URI zones start with %25; raw % is also common in error text.
            if zone.starts(with: [50, 53]) { zone = zone.dropFirst(2) }
            guard !zone.isEmpty else { return false }
            var index = zone.startIndex
            while index < zone.endIndex {
                let byte = zone[index]
                if letter(byte) || (48...57).contains(byte) || "-._~".utf8.contains(byte) {
                    index += 1
                } else if byte == 37, index + 2 < zone.endIndex,
                          isHexDigit(zone[index + 1]), isHexDigit(zone[index + 2]) {
                    index += 3
                } else { return false }
            }
            address = literal[..<percent]
        } else { address = literal }
        // Only the address enters the numeric parser, never a host or zone name.
        // Reject NULs before crossing the C string boundary.
        guard !address.isEmpty, address.allSatisfy({ isHexDigit($0) || $0 == 58 || $0 == 46 }) else { return false }
        var parsed = in6_addr()
        return String(decoding: address, as: UTF8.self).withCString {
            inet_pton(AF_INET6, $0, &parsed) == 1
        }
    }

    private static func decodeStructuralEscapes(_ token: String) -> String {
        var decoded = token
        for (code, value) in [("%3a", ":"), ("%2f", "/"), ("%40", "@"), ("%3f", "?"), ("%23", "#"), ("%5c", "\\"), ("%25", "%")] {
            decoded = decoded.replacingOccurrences(of: code, with: value, options: .caseInsensitive)
        }
        decoded = decoded.replacingOccurrences(of: #"\u002f"#, with: "/", options: .caseInsensitive)
        return decoded.replacingOccurrences(of: "\\/", with: "/")
    }

    private static let encodedStart = try! NSRegularExpression(pattern: #"(?i)(?<![a-z0-9+.-])[a-z][a-z0-9+.-]*(?::(?!//)(?:/|\\{1,2}/|\\u002f|%2f){2}|%3a%2f%2f|%253a%252f%252f|%25253a%25252f%25252f)"#)
    private static let delimiters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'<>"))

    /// Three bounded decoding passes; enumerate markers once per pass. Patterns
    /// that do not match never rescan the remaining suffix for every token.
    private static func normalizeEncodedUrls(_ source: String) -> String {
        var text = source
        for _ in 0..<3 {
            let string = text as NSString
            let matches = encodedStart.matches(in: text, range: NSRange(location: 0, length: string.length))
            guard !matches.isEmpty else { return text }
            var result = ""
            var cursor = 0
            for match in matches where match.range.location >= cursor {
                let lower = match.range.location
                let delimiter = string.rangeOfCharacter(from: delimiters, range: NSRange(location: lower, length: string.length - lower))
                let end = delimiter.location == NSNotFound ? string.length : delimiter.location
                result += string.substring(with: NSRange(location: cursor, length: lower - cursor))
                result += decodeStructuralEscapes(string.substring(with: NSRange(location: lower, length: end - lower)))
                cursor = end
            }
            result += string.substring(from: cursor)
            text = result
        }
        return text
    }
}
