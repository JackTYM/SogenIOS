import Foundation
import NetworkExtension

// Adapted from SideStore/StosVPN's TunnelManager (MIT, attribution required
// -- see README): load-or-create an NETunnelProviderManager for our own
// TunnelExtension and start it, so JITHelper has a real route to
// 10.7.0.1:49152 instead of relying on whatever other VPN happens to be
// active.
private final class ObserverBox {
    var token: NSObjectProtocol?

    func remove() {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
        token = nil
    }
}

enum TunnelManager {
    private static var tunnelBundleId: String {
        Bundle.main.bundleIdentifier!.appending(".TunnelExtension")
    }

    static func ensureConnected(completion: @escaping (Bool, String) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error = error {
                completion(false, "loadAllFromPreferences failed: \(error.localizedDescription)")
                return
            }

            let existing = managers?.first { manager in
                (manager.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == tunnelBundleId
            }

            let manager = existing ?? NETunnelProviderManager()
            if existing == nil {
                manager.localizedDescription = "SogenIOS Tunnel"
                let proto = NETunnelProviderProtocol()
                proto.providerBundleIdentifier = tunnelBundleId
                proto.serverAddress = "SogenIOS Local Network Tunnel"
                manager.protocolConfiguration = proto
            }
            manager.isEnabled = true

            manager.saveToPreferences { error in
                if let error = error {
                    completion(false, "saveToPreferences failed: \(error.localizedDescription)")
                    return
                }

                manager.loadFromPreferences { error in
                    if let error = error {
                        completion(false, "loadFromPreferences failed: \(error.localizedDescription)")
                        return
                    }

                    if manager.connection.status == .connected {
                        completion(true, "already connected")
                        return
                    }

                    let observerBox = ObserverBox()
                    observerBox.token = NotificationCenter.default.addObserver(
                        forName: .NEVPNStatusDidChange, object: manager.connection, queue: .main
                    ) { _ in
                        switch manager.connection.status {
                        case .connected:
                            observerBox.remove()
                            completion(true, "connected")
                        case .disconnected, .invalid:
                            observerBox.remove()
                            completion(false, "tunnel disconnected while starting (status: \(manager.connection.status.rawValue))")
                        default:
                            break
                        }
                    }

                    do {
                        try manager.connection.startVPNTunnel()
                    } catch {
                        observerBox.remove()
                        completion(false, "startVPNTunnel failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}
