import SwiftUI

@main
struct SogenApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                SetupView()
            }
            .onOpenURL { url in
                if url.scheme == "sogenios" {
                    LocalDevVPNManager.handleCallback()
                }
            }
        }
    }
}
