import ExtensionFoundation
import Foundation
import StikJIT
import XPC

private struct JITMessageHandler: XPCPeerHandler {
    func handleIncomingRequest(_ message: JITHelperMessage) -> (any Encodable)? {
        switch message {
        case .pollProgress(let sinceIndex):
            let (lines, nextIndex) = JITProgressBuffer.shared.linesSince(sinceIndex)
            return JITHelperReply.progressLines(lines: lines, nextIndex: nextIndex)

        case .enableJIT(let request):
            let manager = FileManager.default
            let root = manager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("JITHelper", isDirectory: true)
            let pairingURL = root.appendingPathComponent("pairingFile.plist")

            do {
                try manager.createDirectory(at: root, withIntermediateDirectories: true)
                try request.pairingData.write(to: pairingURL, options: .atomic)
            } catch {
                return JITHelperReply.enableJITResult(JITHelperResponse(success: false, message: error.localizedDescription))
            }

            // Started on a background queue rather than run inline (as the old single-shot
            // request/response version did): StikJIT.enableJIT blocks until universal.js's own
            // watch loop exits, i.e. for the rest of this process's life by design (see
            // JITGate.swift's own comment on why jit26_detach() is deliberately never called) --
            // running it inline would starve every later .pollProgress request on this same
            // connection of a chance to be serviced. The host already treats this request's own
            // reply as a "started" acknowledgment, not the real success signal (that's
            // JITGate.prepareRegion's own local self-test) so replying immediately here changes
            // nothing about the app's actual success/failure logic.
            let paths = DDIPaths.default(in: root)
            DispatchQueue.global(qos: .userInitiated).async {
                defer { try? manager.removeItem(at: pairingURL) }
                do {
                    try StikJIT.enableJIT(
                        targetPID: request.targetPID,
                        pairingFile: pairingURL,
                        ddiPaths: paths,
                        script: .universal,
                        progress: {
                            NSLog("[JITHelper] %@", $0)
                            JITProgressBuffer.shared.append($0)
                        })
                    JITProgressBuffer.shared.append("[jithelper] enableJIT finished normally")
                } catch {
                    JITProgressBuffer.shared.append("[jithelper] enableJIT threw: \(error.localizedDescription)")
                }
            }

            return JITHelperReply.enableJITResult(JITHelperResponse(success: true, message: "JIT-grant sequence started."))
        }
    }
}

@main
struct JITHelperExtension: AppExtension {
    @AppExtensionPoint.Bind
    var extensionPoint: AppExtensionPoint {
        AppExtensionPoint.Identifier(host: "com.jacksonyarger.sogenios", name: "JITHelper")
    }

    var configuration: some AppExtensionConfiguration {
        ConnectionHandler(onSessionRequest: { request in
            request.accept { _ in
                JITMessageHandler()
            }
        })
    }
}
