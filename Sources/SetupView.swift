import SwiftUI
import UIKit

struct SetupView: View {
    @State private var logLines: [String] = []
    @State private var emulator: SogenEmulator?
    @State private var pendingLayer: CALayer?
    @State private var bootAttempted = false
    @State private var rootReady = false
    @State private var rootProvisioning = false
    @State private var rootProvisioner: EmulationRootProvisioner?
    @State private var needsLocalDevVPNInstall = false
    @State private var bootedEmulator: SogenEmulator?
    @State private var didBoot = false
    @State private var everBooted = false

    // Neither SwiftUI's .fileImporter nor a directly-wrapped UIDocumentPickerViewController
    // respond to taps on real iPhone hardware under this app's Feather/ArcticSign resigning --
    // confirmed on-device, sheet opens but selecting a file does nothing at all, no highlight,
    // no dismissal. Rather than chase whatever inter-process XPC breakage that resigning causes,
    // this app already sets UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace (see
    // project.yml), which exposes its Documents/ folder directly under Files > On My iPhone >
    // SogenIOS. The pairing file just needs to be moved/copied there via the Files app itself
    // (a plain intra-Files-app operation, no picker UI in this app involved at all); this button
    // re-scans that folder rather than presenting any in-app picker.
    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var pairingFileURL: URL {
        documentsURL.appendingPathComponent("pairingFile.plist")
    }

    // Any regular file dropped into Documents/ that isn't one of this app's own known files is
    // treated as the pairing file, so the user doesn't have to rename it to an exact name.
    private func findDroppedPairingFile() -> URL? {
        let knownNames: Set<String> = ["pairingFile.plist", "sogen_log.txt", "root"]
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
                    // makeUIView runs synchronously inside SwiftUI's view-update pass; mutating
                    // @State here directly is undefined behavior and the write can be silently
                    // lost. Defer to the next run-loop turn instead.
                    DispatchQueue.main.async {
                        pendingLayer = layer
                        attemptBoot()
                    }
                },
                mode: .touchscreen,
                frameSize: .zero,
                onDeliverMove: { _ in },
                onDeliverButton: { _, _ in },
                onDeliverDelta: { _, _ in },
                onDeliverClick: { emulator?.deliverTap() },
                onDeliverRightClick: {}
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(320.0 / 180.0, contentMode: .fit)

            HStack {
                Button("Download Emulation Root") {
                    rootReady = false
                    ensureEmulationRoot()
                }
                .padding(6)
                Button("Check for Pairing File") {
                    checkForPairingFile()
                }
                .padding(6)
                if everBooted {
                    Button("Boot Input Test") {
                        guard let layer = pendingLayer else { return }
                        emulator?.stop()
                        emulator = nil
                        bootedEmulator = nil
                        didBoot = false
                        startEmulator(with: layer, guestResourceName: "mouse-input-test-sample")
                    }
                    .padding(6)
                }
                if needsLocalDevVPNInstall {
                    Button("Install LocalDevVPN") {
                        if let url = URL(string: "https://apps.apple.com/us/app/localdevvpn/id6755608044") {
                            UIApplication.shared.open(url)
                        }
                    }
                    .padding(6)
                    Button("Retry") {
                        needsLocalDevVPNInstall = false
                        bootAttempted = false
                        attemptBoot()
                    }
                    .padding(6)
                }
                Spacer()
            }

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
        .navigationDestination(isPresented: $didBoot) {
            if let emulator = bootedEmulator {
                EmulationView(emulator: emulator, logLines: logLines)
            }
        }
    }

    private func appendLog(_ line: String) {
        logLines.append(line)
        // Mirrored to a file so the log can be pulled via `devicectl device copy from` for
        // evidence without unlocking/screenshotting the phone -- this app has no CLI
        // screenshot path, unlike Xcode's own Devices window.
        sogenMirrorLogLineToFile(line)
    }

    private func checkForPairingFile() {
        let manager = FileManager.default

        if manager.fileExists(atPath: pairingFileURL.path) {
            appendLog("[jit] pairing file already present at \(pairingFileURL.path)")
            bootAttempted = false
            attemptBoot()
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
            // Bundled directly into the IPA (see Resources/pairingFile.plist, gitignored -- the
            // user's own device-pairing credential). No iCloud/picker involved: this is the same
            // local bundle-to-Documents copy already used for the guest .exe and just as durable
            // across reinstalls, unlike a manual Files-app drop which a fresh install wipes.
            do {
                try manager.copyItem(atPath: bundledPath, toPath: pairingFileURL.path)
                appendLog("[jit] pairing file installed from the app bundle to \(pairingFileURL.path)")
            } catch {
                appendLog("ERROR: bundled pairing file install failed: \(error.localizedDescription)")
                return
            }
        } else {
            appendLog("[jit] no pairing file found in Documents -- in the Files app, go to " +
                      "On My iPhone > SogenIOS and move/copy your pairing file there, then tap " +
                      "\"Check for Pairing File\" again")
            return
        }

        // A missing pairing file is the only reason attemptBoot() would have stopped short of
        // starting the JIT-grant sequence, so retry now that one exists.
        bootAttempted = false
        attemptBoot()
    }

    // The upstream sogen project hosts a ready-made emulation root at sogen.dev/root.zip so
    // this app no longer needs it side-loaded over USB. Runs before the pairing-file check
    // since fetching/extracting it has nothing to do with JIT and can happen independently.
    private func ensureEmulationRoot() {
        guard !rootReady else { return }

        if EmulationRootProvisioner.isRootPresent(documents: documentsURL) {
            rootReady = true
            attemptBoot()
            return
        }

        guard !rootProvisioning else { return }
        rootProvisioning = true

        let provisioner = EmulationRootProvisioner(
            log: { line in
                DispatchQueue.main.async { appendLog(line) }
            },
            completion: { result in
                rootProvisioning = false
                switch result {
                case .success:
                    appendLog("[root] emulation root ready")
                    rootReady = true
                    attemptBoot()
                case .failure(let error):
                    appendLog("ERROR: failed to provision emulation root: \(error)")
                }
            })
        rootProvisioner = provisioner
        provisioner.start()
    }

    // Unicorn's own TCG JIT-compiles guest x86 into host ARM64 machine code and executes it
    // directly; on real iOS hardware that first W->X transition is rejected by TXM/SPTM unless
    // this process has already negotiated the JIT26 breakpoint protocol (see Sources/JIT/).
    // This must complete -- or visibly fail -- before windows_emulator is ever constructed;
    // starting the guest without it is a guaranteed CODESIGNING/KERN_PROTECTION_FAILURE crash
    // the moment the guest exercises a code path needing a new translation.
    private func attemptBoot() {
        guard let layer = pendingLayer, emulator == nil, !bootAttempted else { return }

        guard rootReady else {
            ensureEmulationRoot()
            return
        }

#if targetEnvironment(simulator)
        // The Simulator is a plain macOS process with no TXM/SPTM hardware enforcement, so
        // Unicorn's own mmap(PROT_EXEC) already works there unconditionally -- none of JIT26's
        // breakpoint-blessing dance applies. The JIT-grant flow below also can't build for the
        // Simulator at all (JITHelper/TunnelExtension's own dependencies, like StikJIT's vendored
        // libidevice_ffi.a, are real-device-only), so this must be a real branch, not just an
        // early-exit guard reachable through the same code.
        bootAttempted = true
        startEmulator(with: layer)
        return
#else
        // TEMPORARY DIAGNOSTIC BYPASS -- see JITGateOrchestrator.runXcodeDebuggerBypass's own
        // comment. Set via Xcode's scheme editor (Product > Scheme > Edit Scheme > Run >
        // Arguments > Environment Variables) so a normal Xcode Run/attach session can debug
        // Unicorn's real execution bug directly instead of racing our own embedded JIT26 debug
        // session. No pairing file is needed on this path -- it never talks to JITHelper.
        if ProcessInfo.processInfo.environment["SOGEN_JIT26_XCODE_DEBUG_BYPASS"] == "1" {
            bootAttempted = true
            JITGateOrchestrator.runXcodeDebuggerBypass(
                log: { line in DispatchQueue.main.async { appendLog(line) } },
                completion: { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            startEmulator(with: layer)
                        case .tunnelNotInstalled:
                            // Unreachable on this path -- runXcodeDebuggerBypass never touches
                            // TunnelManager/LocalDevVPNManager -- but the switch must be exhaustive.
                            appendLog("ERROR: unexpected tunnelNotInstalled on the Xcode-debugger bypass path")
                        case .failed(let message):
                            appendLog("ERROR: JIT grant failed (Xcode-debugger bypass path), " +
                                      "refusing to start the guest: \(message)")
                        }
                    }
                })
            return
        }

        guard let pairingData = try? Data(contentsOf: pairingFileURL) else {
            // checkForPairingFile() installs the bundled copy automatically on first run (see
            // Resources/pairingFile.plist); it only falls through to the manual Files-app
            // instructions if no bundled copy exists either. Either way it calls back into
            // attemptBoot() on success, so this is a one-shot kick, not a retry loop.
            checkForPairingFile()
            return
        }

        bootAttempted = true
        appendLog("[jit] pairing file found, starting JIT-grant sequence ...")

        JITGateOrchestrator.run(
            pairingData: pairingData,
            log: { line in
                DispatchQueue.main.async { appendLog(line) }
            },
            completion: { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        startEmulator(with: layer)
                    case .tunnelNotInstalled:
                        needsLocalDevVPNInstall = true
                        appendLog("[jit] LocalDevVPN is required for this build's JIT-grant tunnel -- " +
                                  "tap \"Install LocalDevVPN\" below, install it from the App Store, " +
                                  "then tap \"Retry\"")
                    case .failed(let message):
                        appendLog("ERROR: JIT grant failed, refusing to start the guest " +
                                  "(it would crash on the first new Unicorn JIT translation): \(message)")
                    }
                }
            })
#endif
    }

    private func startEmulator(with layer: CALayer, guestResourceName: String = "native-gpu-clear-sample") {
        guard emulator == nil else { return }

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = documents.appendingPathComponent("root").path

        guard let guestPath = Bundle.main.path(forResource: guestResourceName, ofType: "exe") else {
            appendLog("ERROR: \(guestResourceName).exe is not in the app bundle")
            return
        }

        let instance = SogenEmulator(layer: layer, emulationRoot: root, guestExecutablePath: guestPath)
        instance.onLogLine = { line in
            appendLog(line.trimmingCharacters(in: .newlines))
        }
        emulator = instance
        appendLog("[sogen] emulation root: \(root)")
        appendLog("[sogen] guest executable: \(guestPath)")
        instance.start()
        bootedEmulator = instance
        didBoot = true
        everBooted = true
    }
}
