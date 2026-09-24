import SwiftUI
import UIKit

/// Shared across the app's lifetime, not per-view: JIT26's real-device breakpoint-blessing
/// handshake only needs to happen once per process launch, not once per shortcut tap.
final class JITSessionState {
    static let shared = JITSessionState()
    var isGranted = false
    private init() {}
}

struct RootDetailView: View {
    let root: EmulationRoot
    @State private var shortcuts: [GameShortcut] = []
    @State private var editingShortcut: GameShortcut?
    @State private var showingBrowser = false

    @State private var logLines: [String] = []
    @State private var pendingLayer: CALayer?
    @State private var bootAttempted = false
    @State private var needsLocalDevVPNInstall = false
    @State private var bootedEmulator: SogenEmulator?
    @State private var didBoot = false
    @State private var launchingShortcut: GameShortcut?

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var pairingFileURL: URL {
        documentsURL.appendingPathComponent("pairingFile.plist")
    }

    private func findDroppedPairingFile() -> URL? {
        let knownNames: Set<String> = ["pairingFile.plist", "sogen_log.txt", "root", "Roots", "Roots.json"]
        let contents = try? FileManager.default.contentsOfDirectory(
            at: documentsURL, includingPropertiesForKeys: [.isRegularFileKey])
        return contents?.first { url in
            !knownNames.contains(url.lastPathComponent) &&
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            EmulatorView(
                onViewReady: { layer in
                    DispatchQueue.main.async { pendingLayer = layer }
                },
                mode: .touchscreen,
                frameSize: .zero,
                onDeliverMove: { _ in },
                onDeliverButton: { _, _ in },
                onDeliverDelta: { _, _ in },
                onDeliverClick: {},
                onDeliverRightClick: {},
                onCursorPositionChange: { _ in }
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(320.0 / 180.0, contentMode: .fit)

            List {
                ForEach(shortcuts) { shortcut in
                    Button(action: { launchShortcut(shortcut) }) {
                        VStack(alignment: .leading) {
                            Text(shortcut.displayName)
                            Text("\(shortcut.exeRelativePath) · \(shortcut.backend == .fex ? "FEX" : "Unicorn")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            RootStore.shared.deleteShortcut(shortcut.id)
                            reload()
                        }
                        Button("Edit") {
                            editingShortcut = shortcut
                        }
                    }
                }
            }

            HStack {
                Button("+ New Shortcut") {
                    editingShortcut = GameShortcut(
                        id: UUID(), rootID: root.id, displayName: "New Shortcut",
                        exeRelativePath: "", arguments: [], environment: [:], backend: .fex)
                }
                Button("Browse Files") { showingBrowser = true }
                if needsLocalDevVPNInstall {
                    Button("Install LocalDevVPN") {
                        if let url = URL(string: "https://apps.apple.com/us/app/localdevvpn/id6755608044") {
                            UIApplication.shared.open(url)
                        }
                    }
                    Button("Retry") {
                        needsLocalDevVPNInstall = false
                        if let shortcut = launchingShortcut {
                            bootAttempted = false
                            launchShortcut(shortcut)
                        }
                    }
                }
            }
            .padding(6)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(logLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: logLines.count) { count in
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
        .navigationTitle(root.name)
        .onAppear {
            reload()
            // Also fires when popping back from EmulationView (its own back button already
            // stopped that emulator instance) -- without this, bootedEmulator/bootAttempted
            // stay set forever for the rest of this screen's visit, silently no-oping every
            // subsequent tap on any shortcut in the list, including the one that just finished.
            bootedEmulator = nil
            bootAttempted = false
            didBoot = false
            launchingShortcut = nil
        }
        .sheet(item: $editingShortcut) { shortcut in
            NavigationStack {
                ShortcutEditorView(root: root, shortcut: shortcut) { saved in
                    RootStore.shared.upsertShortcut(saved)
                    reload()
                }
            }
        }
        .sheet(isPresented: $showingBrowser) {
            NavigationStack {
                RootFileBrowserView(rootURL: RootStore.shared.filesysCDirectoryURL(for: root))
            }
        }
        .navigationDestination(isPresented: $didBoot) {
            if let emulator = bootedEmulator, let shortcut = launchingShortcut {
                EmulationView(emulator: emulator, logLines: logLines, guestExecutableName: shortcut.exeRelativePath)
            }
        }
    }

    private func reload() {
        shortcuts = RootStore.shared.shortcuts(forRoot: root.id)
    }

    private func appendLog(_ line: String) {
        logLines.append(line)
        sogenMirrorLogLineToFile(line)
    }

    private func checkForPairingFile(then next: @escaping () -> Void) {
        let manager = FileManager.default

        if manager.fileExists(atPath: pairingFileURL.path) {
            appendLog("[jit] pairing file already present at \(pairingFileURL.path)")
            next()
            return
        }

        if let droppedURL = findDroppedPairingFile() {
            do {
                try manager.copyItem(at: droppedURL, to: pairingFileURL)
                try manager.removeItem(at: droppedURL)
                appendLog("[jit] pairing file imported from \(droppedURL.lastPathComponent) to \(pairingFileURL.path)")
            } catch {
                appendLog("ERROR: pairing file import failed: \(error.localizedDescription)")
                return
            }
        } else if let bundledPath = Bundle.main.path(forResource: "pairingFile", ofType: "plist") {
            do {
                try manager.copyItem(atPath: bundledPath, toPath: pairingFileURL.path)
                appendLog("[jit] pairing file installed from the app bundle to \(pairingFileURL.path)")
            } catch {
                appendLog("ERROR: bundled pairing file install failed: \(error.localizedDescription)")
                return
            }
        } else {
            appendLog("[jit] no pairing file found in Documents -- in the Files app, go to " +
                      "On My iPhone > SogenIOS and move/copy your pairing file there, then tap the shortcut again")
            return
        }

        next()
    }

    private func launchShortcut(_ shortcut: GameShortcut) {
        guard let layer = pendingLayer, bootedEmulator == nil, !bootAttempted else { return }
        launchingShortcut = shortcut

        if JITSessionState.shared.isGranted {
            bootAttempted = true
            startEmulator(with: layer, shortcut: shortcut)
            return
        }

#if targetEnvironment(simulator)
        bootAttempted = true
        JITSessionState.shared.isGranted = true
        startEmulator(with: layer, shortcut: shortcut)
        return
#else
        if ProcessInfo.processInfo.environment["SOGEN_JIT26_XCODE_DEBUG_BYPASS"] == "1" {
            bootAttempted = true
            JITGateOrchestrator.runXcodeDebuggerBypass(
                log: { line in DispatchQueue.main.async { appendLog(line) } },
                completion: { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            JITSessionState.shared.isGranted = true
                            startEmulator(with: layer, shortcut: shortcut)
                        case .tunnelNotInstalled:
                            appendLog("ERROR: unexpected tunnelNotInstalled on the Xcode-debugger bypass path")
                        case .failed(let message):
                            bootAttempted = false
                            appendLog("ERROR: JIT grant failed (Xcode-debugger bypass path), " +
                                      "refusing to start the guest: \(message)")
                        }
                    }
                })
            return
        }

        checkForPairingFile {
            guard let pairingData = try? Data(contentsOf: pairingFileURL) else { return }

            bootAttempted = true
            appendLog("[jit] pairing file found, starting JIT-grant sequence ...")

            JITGateOrchestrator.run(
                pairingData: pairingData,
                log: { line in DispatchQueue.main.async { appendLog(line) } },
                completion: { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            JITSessionState.shared.isGranted = true
                            startEmulator(with: layer, shortcut: shortcut)
                        case .tunnelNotInstalled:
                            needsLocalDevVPNInstall = true
                            appendLog("[jit] LocalDevVPN is required for this build's JIT-grant tunnel -- " +
                                      "tap \"Install LocalDevVPN\" below, install it from the App Store, " +
                                      "then tap \"Retry\"")
                        case .failed(let message):
                            bootAttempted = false
                            appendLog("ERROR: JIT grant failed, refusing to start the guest " +
                                      "(it would crash on the first new Unicorn JIT translation): \(message)")
                        }
                    }
                })
        }
#endif
    }

    private func startEmulator(with layer: CALayer, shortcut: GameShortcut) {
        guard bootedEmulator == nil else { return }

        let rootPath = RootStore.shared.directoryURL(for: root).path
        let guestPath = RootStore.shared.filesysCDirectoryURL(for: root)
            .appendingPathComponent(shortcut.exeRelativePath).path

        let instance = SogenEmulator(
            layer: layer, emulationRoot: rootPath, guestExecutablePath: guestPath,
            arguments: shortcut.arguments, environment: shortcut.environment,
            useFEX: shortcut.backend == .fex)
        instance.onLogLine = { line in
            appendLog(line.trimmingCharacters(in: .newlines))
        }
        bootedEmulator = instance
        appendLog("[sogen] emulation root: \(rootPath)")
        appendLog("[sogen] guest executable: \(guestPath)")
        instance.start()
        didBoot = true
    }
}
