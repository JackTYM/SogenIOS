import Foundation
import UIKit

// Provides the same JIT-grant tunnel role as TunnelManager.swift, via LocalDevVPN
// (https://github.com/jkcoxson/LocalDevVPN) -- a separately-installed App Store app that holds
// the Network Extension entitlement TunnelExtension needs but can't get under personal-team
// signing. Intended to be selected instead of TunnelManager when SOGEN_IOS_USE_LOCALDEVVPN is
// set (project.yml); that selection is wired up by a later task in this plan.
// See docs/superpowers/specs/2026-09-16-ios-localdevvpn-design.md.
enum LocalDevVPNResult {
    case connected
    case notInstalled
    case failed(String)
}

final class LocalDevVPNManager {
    static let shared = LocalDevVPNManager()

    private static let probeURL = URL(string: "localdevvpn://")!
    private static let launchURL = URL(string: "localdevvpn://enable?scheme=sogenios")!
    private static let callbackTimeout: TimeInterval = 8

    private var pendingCompletion: ((LocalDevVPNResult) -> Void)?
    private var timeoutWorkItem: DispatchWorkItem?

    private init() {}

    static func ensureConnected(completion: @escaping (LocalDevVPNResult) -> Void) {
        guard UIApplication.shared.canOpenURL(probeURL) else {
            completion(.notInstalled)
            return
        }

        shared.resolve(.failed("superseded by a newer request"))
        shared.pendingCompletion = completion

        let timeoutItem = DispatchWorkItem {
            shared.resolve(.failed("LocalDevVPN did not confirm the tunnel in time"))
        }
        shared.timeoutWorkItem = timeoutItem
        DispatchQueue.main.asyncAfter(deadline: .now() + callbackTimeout, execute: timeoutItem)

        UIApplication.shared.open(launchURL)
    }

    // Intended to be called from an onOpenURL handler (not yet added) when a "sogenios://"
    // callback arrives; that wiring is a separate task in this plan.
    static func handleCallback() {
        shared.resolve(.connected)
    }

    private func resolve(_ result: LocalDevVPNResult) {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        guard let completion = pendingCompletion else { return }
        pendingCompletion = nil
        completion(result)
    }
}
