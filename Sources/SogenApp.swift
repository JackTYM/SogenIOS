import SwiftUI

@main
struct SogenApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    if url.scheme == "sogenios" {
                        LocalDevVPNManager.handleCallback()
                    }
                }
        }
    }
}
