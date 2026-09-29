import SwiftUI

/// A simple, read-only directory browser rooted at a root's filesys/c/ tree. In picker mode
/// (onPickExecutable set), tapping a .exe file calls back with its path relative to `rootURL`;
/// otherwise it's plain browsing (e.g. "Browse Files" from RootDetailView). Deliberately doesn't
/// call `dismiss()` itself: a tap can arrive several NavigationLink pushes deep inside the
/// caller's own presented sheet, and `dismiss()` there would only pop one level of that stack,
/// not close the whole sheet. The caller's `onPickExecutable` closure should flip its own
/// sheet's `isPresented` binding to actually close it, regardless of how deep the user browsed.
struct RootFileBrowserView: View {
    let rootURL: URL
    var onPickExecutable: ((String) -> Void)?

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
                    let rootPath = rootURL.resolvingSymlinksInPath().path
                    let relative = String(entry.resolvingSymlinksInPath().path.dropFirst(rootPath.count + 1))
                    onPickExecutable?(relative)
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
