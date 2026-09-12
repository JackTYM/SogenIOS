import Darwin
import Foundation

// Drives the JIT26 breakpoint protocol (Sources/JIT/JIT26.{c,h}) that the out-of-tree
// spike (.worktrees/ios-jit-test/tools/ios-jit-test/, Test 4/5) proved grants a process
// real W->X execute permission on real iOS 26 hardware, where plain CS_DEBUGGED alone is
// rejected by TXM/SPTM. Unlike the spike's own JITLog (a persistent file log), progress
// here is reported through a caller-supplied sink so it lands in this app's existing
// on-screen log (SogenEmulator.onLogLine / ContentView's logLines).
enum JITGate {
    private static let regionSize = 16384

    // Must be started concurrently with, not after, JITCoordinator.enableJIT's XPC call
    // to the JITHelper extension: the debugger driving the attached script blocks inside
    // its own wait loop until the brk instruction this triggers actually executes, so a
    // sequential "await enableJIT, then prepare the region" ordering deadlocks -- neither
    // side can make progress. This is Test 5's own fix in the spike; run this on a
    // background queue at the same time enableJIT is kicked off, not from its completion.
    static func prepareRegion(log: @escaping (String) -> Void) -> UnsafeMutableRawPointer? {
        let pollInterval: useconds_t = 50_000 // 50ms
        let maxAttempts = 300 // 15s
        var debugged = jit26_is_debugged()
        var attempts = 0
        while !debugged, attempts < maxAttempts {
            usleep(pollInterval)
            debugged = jit26_is_debugged()
            attempts += 1
        }
        log("[jit] CS_DEBUGGED = \(debugged) (after \(attempts) poll(s))")

        guard debugged else {
            log("[jit] timed out waiting for CS_DEBUGGED -- not calling jit26_prepare_region (would crash)")
            return nil
        }

        guard let region = jit26_prepare_region(nil, regionSize) else {
            log("[jit] jit26_prepare_region FAILED (returned null)")
            return nil
        }
        log("[jit] jit26_prepare_region OK at \(region)")

        var kernReturn: Int32 = 0
        var curProt: UInt32 = 0
        var maxProt: UInt32 = 0
        guard let writableAlias = jit26_writable_alias(region, regionSize, &kernReturn, &curProt, &maxProt) else {
            log("[jit] jit26_writable_alias FAILED kern_return=\(kernReturn)")
            return nil
        }

        let writeBit: UInt32 = 0x2 // VM_PROT_WRITE
        guard (curProt & writeBit) != 0 else {
            log("[jit] writable alias lacks VM_PROT_WRITE -- stopping before the write that would crash")
            return nil
        }

        // Writing and later executing a single verification instruction proves this
        // region is genuinely executable, exactly like the spike's Test 4/5 did. Unicorn's
        // own TCG buffer is separate memory it allocates internally; this call's real
        // effect is establishing CS_DEBUGGED + the JIT26 negotiation the process needs so
        // Unicorn's later mmap/mprotect(PROT_EXEC) calls stop being rejected.
        let word = writableAlias.assumingMemoryBound(to: UInt32.self)
        word.pointee = 0xD65F_03C0 // AArch64 RET
        jit_invalidate_icache(region, regionSize)

        // Deliberately NOT calling jit26_detach() here. Doing so would send "D" over the
        // GDB-remote debug session (see universal.js's JIT26Detach), which ends that session's
        // watch loop for good -- and with it, the only thing able to service a *future*
        // jit26_prepare_region() call. Unicorn's own TCG code-gen buffer isn't allocated until
        // well after this self-test completes (see cmake/unicorn-ios-device-jit-shim.c), on a
        // different thread, so the debug session needs to still be attached and watching when
        // that happens. Leaving it attached for the rest of the process's life is deliberate.
        log("[jit] verification write done; leaving the JIT26 debug session attached (not detaching) " +
            "so it can bless Unicorn's own TCG buffer later")

        return region
    }

    static func verifyRegion(_ region: UnsafeMutableRawPointer, log: @escaping (String) -> Void) {
        log("[jit] executing JIT26 verification region ...")
        jit_execute(region)
        log("[jit] JIT26 verification region executed successfully")
    }
}

enum JITGateOrchestrator {
    // End-to-end sequence ported from the spike's ContentView.attemptBuiltInJIT/
    // startBuiltInJIT (Test 5): tunnel up, then the concurrent enableJIT/prepareRegion
    // pair, then verify. Calls completion(true) only once the JIT26 region has actually
    // been proven executable; completion(false, reason) otherwise, and the emulator must
    // not be started in that case.
    //
    // JITCoordinator.enableJIT's XPC reply arrives almost immediately (an ack that the JIT26
    // debug session has started, not that it's done -- see JITHelperExtension.swift's own
    // comment: universal.js's watch loop keeps running, attached, for the rest of the process's
    // life in the success case, same as before). So completion here is still driven purely by
    // the *local* self-test (prepareRegion + verifyRegion) succeeding, not by enableJIT's XPC
    // reply. What changed is visibility: onProgressLine below receives every one of universal.js's
    // own log() lines for as long as the session stays attached (polled over the same XPC
    // connection -- see JITCoordinator.swift), not just this one ack.
    static func run(pairingData: Data, log: @escaping (String) -> Void, completion: @escaping (Bool, String) -> Void) {
        log("[jit] starting tunnel extension ...")
        TunnelManager.ensureConnected { tunnelUp, tunnelMessage in
            log("[jit] tunnel \(tunnelUp ? "up" : "FAILED"): \(tunnelMessage)")
            guard tunnelUp else {
                completion(false, "tunnel failed to start: \(tunnelMessage)")
                return
            }

            log("[jit] calling JITHelper (XPC) -- preparing the JIT26 region concurrently, not after")

            JITCoordinator.enableJIT(
                targetPID: getpid(), pairingData: pairingData,
                onProgressLine: log,
                completion: { success, message in
                    log("[jit] JITHelper acknowledged the enableJIT request (success=\(success)): \(message)")
                })

            DispatchQueue.global(qos: .userInitiated).async {
                guard let region = JITGate.prepareRegion(log: log) else {
                    completion(false, "JIT26 self-test region prepare failed")
                    return
                }
                JITGate.verifyRegion(region, log: log)
                log("[jit] JIT26 self-test verified; debug session stays attached for Unicorn")
                completion(true, "JIT26 self-test verified")
            }
        }
    }

    // TEMPORARY DIAGNOSTIC BYPASS -- do not use for the shipping app. Added for the pivot to
    // debugging Unicorn's real TCG execution bug via Xcode's own attached LLDB session instead
    // of our embedded JITHelper/tunnel flow: two debuggers can't attach to the same process, so
    // this skips ever starting our own JIT26 debug session (TunnelManager/JITCoordinator above)
    // entirely. Xcode's own debugger attaching over USB during a normal Run sets CS_DEBUGGED the
    // same way our embedded session does, so JITGate.prepareRegion's existing poll/prepare/
    // verify sequence below is reused completely unchanged -- only the tunnel/XPC machinery that
    // spins up OUR OWN debug session is skipped. See ContentView.attemptBoot for the
    // SOGEN_JIT26_XCODE_DEBUG_BYPASS environment variable that selects this path. Remove once the
    // real bug is found and go back to run() above for the shipping self-contained flow.
    static func runXcodeDebuggerBypass(log: @escaping (String) -> Void, completion: @escaping (Bool, String) -> Void) {
        log("[jit] SOGEN_JIT26_XCODE_DEBUG_BYPASS set -- skipping the embedded tunnel/JITHelper " +
            "flow, waiting for Xcode's own debugger to attach instead")
        DispatchQueue.global(qos: .userInitiated).async {
            guard let region = JITGate.prepareRegion(log: log) else {
                completion(false, "JIT26 self-test region prepare failed")
                return
            }
            JITGate.verifyRegion(region, log: log)
            log("[jit] JIT26 self-test verified (Xcode-debugger bypass path)")
            completion(true, "JIT26 self-test verified")
        }
    }
}
