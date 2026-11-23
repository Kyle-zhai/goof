import Foundation

public enum MessageRules {
    /// Danmaku should be short. Mirrored by a check constraint on the server.
    public static let maxLength = 80

    public enum ValidationError: Error, Equatable {
        case empty
        case tooLong(limit: Int)
    }

    /// Trims, strips control characters and collapses whitespace runs.
    public static func normalize(_ raw: String) -> String {
        // Drop C0/C1 control characters (but keep format characters such as the
        // zero-width joiner used by emoji), then collapse whitespace runs.
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            if scalar.properties.isWhitespace {
                scalars.append(" ")
            } else if scalar.properties.generalCategory != .control {
                scalars.append(scalar)
            }
        }
        return String(scalars).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    public static func validate(_ raw: String) -> Result<String, ValidationError> {
        let text = normalize(raw)
        if text.isEmpty { return .failure(.empty) }
        if text.count > maxLength { return .failure(.tooLong(limit: maxLength)) }
        return .success(text)
    }
}

/// Client-side mirror of the server's rate limit so the UI can explain a
/// rejection before a round trip. The server remains the source of truth.
public struct SendRateLimiter: Sendable {
    public enum Decision: Sendable, Equatable {
        case allowed
        case tooFast(retryAfter: TimeInterval)
        case duplicate
    }

    public var minInterval: TimeInterval
    public var maxPerMinute: Int
    private var sent: [(text: String, at: Date)] = []

    public init(minInterval: TimeInterval = 3, maxPerMinute: Int = 12) {
        self.minInterval = minInterval
        self.maxPerMinute = maxPerMinute
    }

    public func check(_ text: String, at now: Date) -> Decision {
        let recent = sent.filter { now.timeIntervalSince($0.at) < 60 }
        if let last = recent.last {
            let elapsed = now.timeIntervalSince(last.at)
            if elapsed < minInterval { return .tooFast(retryAfter: minInterval - elapsed) }
            if last.text == text, elapsed < 30 { return .duplicate }
        }
        if recent.count >= maxPerMinute, let oldest = recent.first {
            return .tooFast(retryAfter: 60 - now.timeIntervalSince(oldest.at))
        }
        return .allowed
    }

    public mutating func record(_ text: String, at now: Date) {
        sent.append((text, now))
        sent.removeAll { now.timeIntervalSince($0.at) >= 60 }
    }
}
