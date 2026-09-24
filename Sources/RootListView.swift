import SwiftUI

struct RootListView: View {
    @State private var roots: [EmulationRoot] = RootStore.shared.roots
    @State private var showingAddRoot = false
    @State private var newRootName = ""
    @State private var duplicateSourceID: UUID?
    @State private var creator: EmulationRootCreator?
    @State private var creationLog: [String] = []
    @State private var isCreating = false

    var body: some View {
        List {
            ForEach(roots) { root in
                NavigationLink(root.name) {
                    RootDetailView(root: root)
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        RootStore.shared.deleteRoot(root.id)
                        roots = RootStore.shared.roots
                    }
                }
            }
            Button("+ Add Root") {
                newRootName = ""
                duplicateSourceID = nil
                creationLog = []
                showingAddRoot = true
            }
            NavigationLink("Controller Layouts") {
                ArcadeProfileListView()
            }
        }
        .navigationTitle("Emulation Roots")
        .sheet(isPresented: $showingAddRoot) {
            addRootSheet
        }
    }

    private var addRootSheet: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Root Name", text: $newRootName)
                }
                if !roots.isEmpty {
                    Section("Duplicate an existing root instead") {
                        Picker("Source", selection: $duplicateSourceID) {
                            Text("None (fresh download)").tag(UUID?.none)
                            ForEach(roots) { root in
                                Text(root.name).tag(Optional(root.id))
                            }
                        }
                    }
                }
                if isCreating {
                    Section("Progress") {
                        ForEach(Array(creationLog.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 11, design: .monospaced))
                        }
                    }
                }
            }
            .navigationTitle("Add Root")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createRoot() }
                        .disabled(newRootName.isEmpty || isCreating)
                }
            }
        }
    }

    private func createRoot() {
        isCreating = true
        creationLog = []
        let name = newRootName
        let sourceID = duplicateSourceID
        let source = sourceID.flatMap { id in roots.first(where: { $0.id == id }) }

        let creator = EmulationRootCreator(
            log: { line in DispatchQueue.main.async { creationLog.append(line) } },
            completion: { result in
                DispatchQueue.main.async {
                    isCreating = false
                    switch result {
                    case .success:
                        roots = RootStore.shared.roots
                        showingAddRoot = false
                    case .failure(let error):
                        creationLog.append("ERROR: \(error.localizedDescription)")
                    }
                }
            })
        self.creator = creator

        if let source {
            creator.duplicate(source, named: name)
        } else {
            creator.createFresh(named: name)
        }
    }
}
