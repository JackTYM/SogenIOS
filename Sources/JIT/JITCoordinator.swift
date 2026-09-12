import ExtensionFoundation
import Foundation
import XPC

@available(iOS 26.0, *)
private final class JITHelperSession {
    let process: AppExtensionProcess
    let session: XPCSession

    init(process: AppExtensionProcess, session: XPCSession) {
        self.process = process
        self.session = session
    }

    deinit {
        session.cancel(reason: "JIT request finished")
        process.invalidate()
    }
}

enum JITCoordinator {
    private static var activeSession: AnyObject?
    private static var progressPollTimer: Timer?
    private static var progressPollCursor = 0

    // onProgressLine fires for every one of universal.js's own log() lines (see
    // JITProgressBuffer.swift/JITHelperExtension.swift), not just the final enableJIT
    // success/failure -- polled over the same XPC session the original request used, since
    // XPCSession has no facility for JITHelper to push these to us unprompted. completion still
    // fires once for the initial "JIT-grant sequence started" acknowledgment only; per
    // JITGateOrchestrator's own long-standing design, the real success signal is JITGate's local
    // self-test, not this XPC reply.
    static func enableJIT(targetPID: Int32, pairingData: Data,
                           onProgressLine: @escaping (String) -> Void,
                           completion: @escaping (Bool, String) -> Void) {
        guard #available(iOS 26.0, *) else {
            completion(false, "Built-in JIT requires iOS 26 or later.")
            return
        }

        Task { @MainActor in
            do {
                let monitor = try await AppExtensionPoint.Monitor(appExtensionPoint: .jitHelper)
                guard let identity = monitor.identities.first else {
                    throw NSError(
                        domain: "JITCoordinator", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "JIT Helper extension was not found in this installation."])
                }

                let process = try await AppExtensionProcess(configuration: .init(
                    appExtensionIdentity: identity,
                    onInterruption: {
                        activeSession = nil
                        progressPollTimer?.invalidate()
                        progressPollTimer = nil
                    }))
                let xpcSession = try process.makeXPCSession()
                try xpcSession.activate()
                activeSession = JITHelperSession(process: process, session: xpcSession)

                let request = JITHelperRequest(targetPID: targetPID, pairingData: pairingData)
                try xpcSession.send(JITHelperMessage.enableJIT(request)) { (result: Result<JITHelperReply, any Error>) in
                    switch result {
                    case .success(.enableJITResult(let response)):
                        DispatchQueue.main.async { completion(response.success, response.message) }
                    case .success(.progressLines):
                        DispatchQueue.main.async { completion(false, "unexpected reply to enableJIT request") }
                    case .failure(let error):
                        DispatchQueue.main.async { completion(false, error.localizedDescription) }
                    }
                }

                progressPollCursor = 0
                progressPollTimer?.invalidate()
                progressPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                    pollProgress(session: xpcSession, onProgressLine: onProgressLine)
                }
            } catch {
                activeSession = nil
                completion(false, error.localizedDescription)
            }
        }
    }

    @available(iOS 26.0, *)
    private static func pollProgress(session: XPCSession, onProgressLine: @escaping (String) -> Void) {
        do {
            try session.send(JITHelperMessage.pollProgress(sinceIndex: progressPollCursor)) { (result: Result<JITHelperReply, any Error>) in
                guard case .success(.progressLines(let lines, let nextIndex)) = result else {
                    return
                }
                progressPollCursor = nextIndex
                guard !lines.isEmpty else {
                    return
                }
                DispatchQueue.main.async {
                    for line in lines {
                        onProgressLine(line)
                    }
                }
            }
        } catch {
            // The extension process (and its XPC session) is gone -- nothing more to poll.
            progressPollTimer?.invalidate()
            progressPollTimer = nil
        }
    }
}
