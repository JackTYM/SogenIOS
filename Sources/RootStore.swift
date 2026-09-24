import Foundation

final class RootStore {
    static let shared = RootStore()

    private(set) var roots: [EmulationRoot]
    private(set) var shortcuts: [GameShortcut]

    private let fileURL: URL
    let rootsDirectory: URL

    private struct PersistedState: Codable {
        var roots: [EmulationRoot]
        var shortcuts: [GameShortcut]
    }

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = documents.appendingPathComponent("Roots.json")
        self.rootsDirectory = documents.appendingPathComponent("Roots")
        try? FileManager.default.createDirectory(at: rootsDirectory, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(PersistedState.self, from: data) {
            self.roots = decoded.roots
            self.shortcuts = decoded.shortcuts
        } else {
            self.roots = []
            self.shortcuts = []
        }
    }

    private func save() {
        let state = PersistedState(roots: roots, shortcuts: shortcuts)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Sanitizes a name into a filesystem-safe folder name, appending a numeric suffix on
    /// collision so Documents/Roots/<folder>/ stays unique and human-readable in the Files app.
    /// Checks both the in-memory roots list AND the real filesystem (APFS is case-insensitive,
    /// and a directory can be orphaned on disk with no in-memory root at all if a prior
    /// deleteRoot's best-effort removeItem silently failed) -- excludingRootID's own current
    /// folder is skipped in both checks so renaming a root back to its own name isn't treated
    /// as a collision with itself.
    private func availableFolderName(for name: String, excludingRootID: UUID?) -> String {
        let excludedFolderName = roots.first(where: { $0.id == excludingRootID })?.folderName

        let sanitized = name.replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = sanitized.isEmpty ? "Root" : sanitized
        var candidate = base
        var suffix = 2
        while isFolderNameTaken(candidate, excludingRootID: excludingRootID, excludingFolderName: excludedFolderName) {
            candidate = "\(base) \(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func isFolderNameTaken(_ candidate: String, excludingRootID: UUID?, excludingFolderName: String?) -> Bool {
        if candidate.caseInsensitiveCompare(excludingFolderName ?? "") == .orderedSame {
            return false
        }
        let inMemoryCollision = roots.contains {
            $0.id != excludingRootID && $0.folderName.caseInsensitiveCompare(candidate) == .orderedSame
        }
        let onDiskCollision = FileManager.default.fileExists(atPath: rootsDirectory.appendingPathComponent(candidate).path)
        return inMemoryCollision || onDiskCollision
    }

    func directoryURL(for root: EmulationRoot) -> URL {
        rootsDirectory.appendingPathComponent(root.folderName)
    }

    func filesysCDirectoryURL(for root: EmulationRoot) -> URL {
        directoryURL(for: root).appendingPathComponent("filesys/c")
    }

    func addRoot(named name: String) -> EmulationRoot {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folderName = availableFolderName(for: trimmedName, excludingRootID: nil)
        let root = EmulationRoot(id: UUID(), name: trimmedName, folderName: folderName, createdAt: Date())
        roots.append(root)
        save()
        return root
    }

    func renameRoot(_ rootID: UUID, to newName: String) throws {
        guard let index = roots.firstIndex(where: { $0.id == rootID }) else { return }
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldURL = directoryURL(for: roots[index])
        let newFolderName = availableFolderName(for: trimmedName, excludingRootID: rootID)
        let newURL = rootsDirectory.appendingPathComponent(newFolderName)
        if FileManager.default.fileExists(atPath: oldURL.path) {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
        }
        roots[index].name = trimmedName
        roots[index].folderName = newFolderName
        save()
    }

    func deleteRoot(_ rootID: UUID) {
        guard let root = roots.first(where: { $0.id == rootID }) else { return }
        try? FileManager.default.removeItem(at: directoryURL(for: root))
        roots.removeAll { $0.id == rootID }
        shortcuts.removeAll { $0.rootID == rootID }
        save()
    }

    func shortcuts(forRoot rootID: UUID) -> [GameShortcut] {
        shortcuts.filter { $0.rootID == rootID }
    }

    func upsertShortcut(_ shortcut: GameShortcut) {
        if let index = shortcuts.firstIndex(where: { $0.id == shortcut.id }) {
            shortcuts[index] = shortcut
        } else {
            shortcuts.append(shortcut)
        }
        save()
    }

    func deleteShortcut(_ shortcutID: UUID) {
        shortcuts.removeAll { $0.id == shortcutID }
        save()
    }
}
