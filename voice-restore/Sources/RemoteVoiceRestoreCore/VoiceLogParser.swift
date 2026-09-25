import Foundation

/// A single interesting event decoded from a SayAll runtime.log line.
public enum VoiceLogEvent: Equatable, Sendable {
    /// Physical remote microphone stream, independent of Fn injection.
    case remoteStreamStart(session: String)
    case remoteStreamStop(session: String)
    /// "VOICE INPUT function_key edge=down tool=<tool>"
    case functionKeyDown(tool: String)
    /// "VOICE INPUT function_key edge=up tool=<tool>"
    case functionKeyUp(tool: String)
    /// Line is not a voice function-key event (or unparseable).
    case ignored
}

/// Deterministic parser for the SayAll runtime.log lines we care about.
///
/// Example event (SayAll 1.9.21 format):
///   VOICE INPUT function_key edge=down tool=doubao
public enum VoiceLogParser {
    private static let streamPattern = #"ATVV STREAM (START|STOP) session=([0-9]+)"#
    /// Matches "function_key edge=down/up tool=<name>" inside a "VOICE INPUT" line.
    private static let pattern =
        #"VOICE INPUT function_key edge=(down|up) tool=([A-Za-z0-9_]+)"#

    public static func parse(line: String) -> VoiceLogEvent {
        if line.contains("ATVV STREAM"),
           let regex = try? NSRegularExpression(pattern: streamPattern) {
            let ns = line as NSString
            if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges == 3 {
                let edge = ns.substring(with: match.range(at: 1))
                let session = ns.substring(with: match.range(at: 2))
                return edge == "START" ? .remoteStreamStart(session: session) : .remoteStreamStop(session: session)
            }
        }
        guard line.contains("VOICE INPUT") else { return .ignored }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return .ignored }
        let ns = line as NSString
        guard let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges == 3 else {
            return .ignored
        }
        let edge = ns.substring(with: match.range(at: 1))
        let tool = ns.substring(with: match.range(at: 2))
        switch edge {
        case "down": return .functionKeyDown(tool: tool)
        case "up": return .functionKeyUp(tool: tool)
        default: return .ignored
        }
    }
}
