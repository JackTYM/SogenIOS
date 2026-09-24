import SwiftUI

@main
struct SogenApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                RootListView()
            }
            .onOpenURL { url in
                if url.scheme == "sogenios" {
                    LocalDevVPNManager.handleCallback()
                }
            }
        }
    }
}
