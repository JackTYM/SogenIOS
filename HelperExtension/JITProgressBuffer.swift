import Foundation

// Backs the polling side of the progress-log protocol in JITMessage.swift. This process (the
// JITHelper extension) has no App Group / shared container available (the paid developer account
// behind the user's resigning cert isn't under our control, so we can't register one) and
// XPCSession has no way to push unsolicited messages back to the host's session (confirmed by
// inspecting XPC.framework's own symbol table: AppExtensionProcess.makeXPCSession() takes no
// configuration, and XPCSession exposes no settable incomingMessageHandler post-construction) --
// so the host has to ask for new lines instead of us pushing them. universal.js's own log() calls
// (via StikJIT's progress: closure) are appended here from whatever background thread is running
// the JIT26 debug session; JITCoordinator on the host side polls linesSince(_:) periodically over
// the same XPC connection the original enableJIT request used.
final class JITProgressBuffer: @unchecked Sendable {
    static let shared = JITProgressBuffer()

    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    func linesSince(_ index: Int) -> (lines: [String], nextIndex: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard index < lines.count else {
            return ([], lines.count)
        }
        return (Array(lines[index...]), lines.count)
    }
}
