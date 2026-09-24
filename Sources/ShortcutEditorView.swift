import SwiftUI

/// Create/edit form for one GameShortcut within a specific root. Not shown over a live guest --
/// pure metadata editing, matching ArcadeProfileEditorView's separate-screen pattern.
struct ShortcutEditorView: View {
    let root: EmulationRoot
    @State var shortcut: GameShortcut
    let onSave: (GameShortcut) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var argumentsText: String
    @State private var environmentText: String
    @State private var showingBrowser = false

    init(root: EmulationRoot, shortcut: GameShortcut, onSave: @escaping (GameShortcut) -> Void) {
        self.root = root
        self._shortcut = State(initialValue: shortcut)
        self.onSave = onSave
        self._argumentsText = State(initialValue: shortcut.arguments.joined(separator: " "))
        self._environmentText = State(initialValue:
            shortcut.environment.map { "\($0.key)=\($0.value)" }.joined(separator: "\n"))
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Display Name", text: $shortcut.displayName)
            }
            Section("Executable") {
                Text(shortcut.exeRelativePath.isEmpty ? "(none selected)" : shortcut.exeRelativePath)
                    .foregroundColor(shortcut.exeRelativePath.isEmpty ? .secondary : .primary)
                Button("Browse...") { showingBrowser = true }
            }
            Section("Arguments") {
                TextField("space-separated, e.g. -novid -windowed", text: $argumentsText)
            }
            Section("Environment Variables") {
                TextEditor(text: $environmentText)
                    .frame(minHeight: 80)
                Text("One KEY=VALUE per line")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section("Backend") {
                Picker("Backend", selection: $shortcut.backend) {
                    Text("FEX").tag(BackendChoice.fex)
                    Text("Unicorn").tag(BackendChoice.unicorn)
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle("Edit Shortcut")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    applyTextFields()
                    onSave(shortcut)
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showingBrowser) {
            NavigationStack {
                RootFileBrowserView(rootURL: RootStore.shared.filesysCDirectoryURL(for: root)) { relativePath in
                    shortcut.exeRelativePath = relativePath
                    showingBrowser = false
                }
            }
        }
    }

    private func applyTextFields() {
        shortcut.arguments = argumentsText.split(separator: " ").map(String.init)
        var env: [String: String] = [:]
        for line in environmentText.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                env[String(parts[0])] = String(parts[1])
            }
        }
        shortcut.environment = env
    }
}
