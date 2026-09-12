import Foundation

// Two message shapes over the SAME XPC session/connection JITCoordinator already establishes to
// JITHelper: the original enableJIT request/response, plus a poll request the host repeats on a
// timer to drain JITHelper's own JITProgressBuffer (the extension's universal.js progress lines --
// see JITProgressBuffer.swift for why this is polling rather than a push: XPCSession has no
// facility for the extension to send the host unsolicited messages on this connection).
public enum JITHelperMessage: Codable, Sendable {
    case enableJIT(JITHelperRequest)
    case pollProgress(sinceIndex: Int)
}

public struct JITHelperRequest: Codable, Sendable {
    public let targetPID: Int32
    public let pairingData: Data

    public init(targetPID: Int32, pairingData: Data) {
        self.targetPID = targetPID
        self.pairingData = pairingData
    }
}

public enum JITHelperReply: Codable, Sendable {
    case enableJITResult(JITHelperResponse)
    case progressLines(lines: [String], nextIndex: Int)
}

public struct JITHelperResponse: Codable, Sendable {
    public let success: Bool
    public let message: String

    public init(success: Bool, message: String) {
        self.success = success
        self.message = message
    }
}
