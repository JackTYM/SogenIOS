import Foundation

enum BackendChoice: String, Codable {
    case fex
    case unicorn
}

struct EmulationRoot: Codable, Identifiable {
    var id: UUID
    var name: String
    // The actual on-disk directory name under Documents/Roots/ -- may differ from `name` only
    // via a numeric collision suffix ("Dev Sandbox 2"). Kept in sync with the real directory on
    // every rename by RootStore, since this is what the user actually sees and navigates to in
    // the Files app to drop files in.
    var folderName: String
    var createdAt: Date
}

struct GameShortcut: Codable, Identifiable {
    var id: UUID
    var rootID: UUID
    var displayName: String
    var exeRelativePath: String   // relative to <root folder>/filesys/c/
    var arguments: [String]
    var environment: [String: String]
    var backend: BackendChoice
}
