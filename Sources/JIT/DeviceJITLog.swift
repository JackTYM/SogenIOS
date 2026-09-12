import Foundation

// Guards the file below: appendLog's own writes arrive dispatched onto the main queue (one at a
// time, but from a different call path than this one), while sogen_jit26_device_log below is
// called directly and synchronously from arbitrary background emulator threads -- without this,
// two writes landing at the same instant could interleave mid-write (open/seek/write/close is not
// atomic across threads).
private let sogenLogFileLock = NSLock()

// Mirrors a log line to the same Documents/sogen_log.txt file ContentView.appendLog writes to,
// via FileManager's own sandbox-correct Documents URL rather than re-deriving the path by hand on
// the C/C++ side (an earlier revision of this mechanism did that with getenv("HOME"), and it
// produced zero visible log output on a real device run -- indistinguishable from the code that
// was supposed to log never running at all). src/backends/unicorn-emulator/ios_device_jit_bless.cpp
// calls into this (via the @_cdecl bridge below) so its diagnostic log lines are guaranteed to
// land in the same exportable file ContentView's own [jit]/[sogen] lines do.
//
// synchronizeFile() (fsync) runs after every write rather than relying on the default write(2)
// behavior alone: the failure mode this log exists to diagnose is the app hanging and later being
// force-quit, not a clean exit, so every line needs to survive that without depending on how much
// of it made it from the kernel's page cache to storage before the process disappears.
func sogenMirrorLogLineToFile(_ line: String) {
    sogenLogFileLock.lock()
    defer { sogenLogFileLock.unlock() }

    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let logURL = documents.appendingPathComponent("sogen_log.txt")
    let entry = line + "\n"
    guard let data = entry.data(using: .utf8) else { return }
    if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.synchronize()
        try? handle.close()
    } else {
        try? data.write(to: logURL)
    }
}

// Called from src/backends/unicorn-emulator/ios_device_jit_bless.cpp, part of the
// `unicorn-emulator` CMake static library (a different CMake/Xcode target than this file) and
// tied to this symbol only at final link time inside the app's own Mach-O image -- see that
// file's own top-of-file comment.
@_cdecl("sogen_jit26_device_log")
func sogenJIT26DeviceLog(_ line: UnsafePointer<CChar>) {
    sogenMirrorLogLineToFile(String(cString: line))
}
