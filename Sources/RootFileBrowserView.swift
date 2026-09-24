import SwiftUI

/// A simple, read-only directory browser rooted at a root's filesys/c/ tree. In picker mode
/// (onPickExecutable set), tapping a .exe file calls back with its path relative to `rootURL`
/// and dismisses; otherwise it's plain browsing (e.g. "Browse Files" from RootDetailView).
struct RootFileBrowserView: View {
    let rootURL: URL
    var onPickExecutable: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var currentDirectory: URL
    @State private var entries: [URL] = []

    init(rootURL: URL, startingAt: URL? = nil, onPickExecutable: ((String) -> Void)? = nil) {
        self.rootURL = rootURL
        self.onPickExecutable = onPickExecutable
        self._currentDirectory = State(initialValue: startingAt ?? rootURL)
    }

    var body: some View {
        List(entries, id: \.self) { entry in
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                NavigationLink(entry.lastPathComponent) {
                    RootFileBrowserView(rootURL: rootURL, startingAt: entry, onPickExecutable: onPickExecutable)
                }
            } else {
                let isExecutable = entry.pathExtension.lowercased() == "exe"
                Button(entry.lastPathComponent) {
                    guard onPickExecutable != nil, isExecutable else { return }
                    let relative = String(entry.path.dropFirst(rootURL.path.count + 1))
                    onPickExecutable?(relative)
                    dismiss()
                }
                .foregroundColor(isExecutable ? .primary : .secondary)
            }
        }
        .navigationTitle(currentDirectory.lastPathComponent)
        .onAppear { reload() }
    }

    private func reload() {
        let fm = FileManager.default
        let contents = try? fm.contentsOfDirectory(at: currentDirectory, includingPropertiesForKeys: [.isDirectoryKey])
        entries = (contents ?? []).sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }
}
