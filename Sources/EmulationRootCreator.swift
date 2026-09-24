import Foundation

/// Creates a new EmulationRoot: either a fresh download of the base environment, or a
/// duplicate of an existing root's directory tree (including its shortcuts). Fresh roots get
/// the two bundled sample .exe's seeded into filesys/c/ with matching default shortcuts, so
/// every fresh root has real, immediately-testable content -- this is what "Boot Input Test"
/// becomes.
final class EmulationRootCreator {
    private let log: (String) -> Void
    private let completion: (Result<EmulationRoot, Error>) -> Void
    private var provisioner: EmulationRootProvisioner?

    init(log: @escaping (String) -> Void, completion: @escaping (Result<EmulationRoot, Error>) -> Void) {
        self.log = log
        self.completion = completion
    }

    func createFresh(named name: String) {
        let root = RootStore.shared.addRoot(named: name)
        let destination = RootStore.shared.directoryURL(for: root)

        let provisioner = EmulationRootProvisioner(
            destinationRoot: destination,
            log: log,
            completion: { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.seedSamples(into: root)
                    self.completion(.success(root))
                case .failure(let error):
                    RootStore.shared.deleteRoot(root.id)
                    self.completion(.failure(error))
                }
            })
        self.provisioner = provisioner
        provisioner.start()
    }

    func duplicate(_ sourceRoot: EmulationRoot, named name: String) {
        let root = RootStore.shared.addRoot(named: name)
        let destination = RootStore.shared.directoryURL(for: root)
        let source = RootStore.shared.directoryURL(for: sourceRoot)
        let sourceShortcuts = RootStore.shared.shortcuts(forRoot: sourceRoot.id)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                self.log("[root] duplicating \(sourceRoot.name) ...")
                try FileManager.default.copyItem(at: source, to: destination)
                self.log("[root] duplicate complete")
                DispatchQueue.main.async {
                    for shortcut in sourceShortcuts {
                        var copy = shortcut
                        copy.id = UUID()
                        copy.rootID = root.id
                        RootStore.shared.upsertShortcut(copy)
                    }
                    self.completion(.success(root))
                }
            } catch {
                RootStore.shared.deleteRoot(root.id)
                DispatchQueue.main.async {
                    self.completion(.failure(error))
                }
            }
        }
    }

    private func seedSamples(into root: EmulationRoot) {
        let fm = FileManager.default
        let filesysC = RootStore.shared.filesysCDirectoryURL(for: root)
        try? fm.createDirectory(at: filesysC, withIntermediateDirectories: true)

        let samples = ["native-gpu-clear-sample", "mouse-input-test-sample"]
        for sample in samples {
            guard let bundlePath = Bundle.main.path(forResource: sample, ofType: "exe") else { continue }
            let destination = filesysC.appendingPathComponent("\(sample).exe")
            try? fm.copyItem(atPath: bundlePath, toPath: destination.path)

            let shortcut = GameShortcut(
                id: UUID(), rootID: root.id, displayName: sample, exeRelativePath: "\(sample).exe",
                arguments: [], environment: [:], backend: .fex)
            RootStore.shared.upsertShortcut(shortcut)
        }
    }
}
