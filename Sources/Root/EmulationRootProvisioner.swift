import Foundation

enum EmulationRootProvisionError: Error, CustomStringConvertible {
    case httpStatus(Int)
    case moveFailed(String)

    var description: String {
        switch self {
        case .httpStatus(let code):
            return "download failed with HTTP status \(code)"
        case .moveFailed(let reason):
            return "could not move downloaded file: \(reason)"
        }
    }
}

// Downloads the upstream sogen project's ready-made emulation root (documented in the repo's
// root/README.md) so the app doesn't need it side-loaded over USB, then extracts it into
// <Documents>/root. Extraction lands in a scratch directory first and is only moved into place
// once it fully succeeds, so a failed attempt never leaves a half-extracted root that a later
// `filesys`+`registry` presence check would mistake for a real one.
final class EmulationRootProvisioner: NSObject, URLSessionDownloadDelegate {
    static let rootZipURL = URL(string: "https://sogen.dev/root.zip")!

    private let log: (String) -> Void
    private let completion: (Result<Void, Error>) -> Void
    private var lastLoggedBucket = -1
    private var session: URLSession?

    init(log: @escaping (String) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        self.log = log
        self.completion = completion
    }

    static func isRootPresent(documents: URL) -> Bool {
        let root = documents.appendingPathComponent("root")
        let fm = FileManager.default

        var isDirectory: ObjCBool = false
        let filesysPresent = fm.fileExists(atPath: root.appendingPathComponent("filesys").path, isDirectory: &isDirectory)
            && isDirectory.boolValue
        let registryPresent = fm.fileExists(atPath: root.appendingPathComponent("registry").path, isDirectory: &isDirectory)
            && isDirectory.boolValue
        return filesysPresent && registryPresent
    }

    func start() {
        log("[root] emulation root not found, downloading \(Self.rootZipURL.absoluteString) ...")
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        session.downloadTask(with: Self.rootZipURL).resume()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let percent = Int((Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) * 100)
        let bucket = (percent / 5) * 5
        guard bucket != lastLoggedBucket, bucket > 0 else { return }
        lastLoggedBucket = bucket
        log("[root] downloading ... \(bucket)%")
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let fm = FileManager.default

        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            finish(.failure(EmulationRootProvisionError.httpStatus(http.statusCode)))
            return
        }

        // URLSession deletes the file at `location` as soon as this delegate method returns,
        // so it must be moved out synchronously, not merely scheduled for later.
        let tempZip = fm.temporaryDirectory.appendingPathComponent("sogen-root-\(UUID().uuidString).zip")
        do {
            try fm.moveItem(at: location, to: tempZip)
        } catch {
            finish(.failure(EmulationRootProvisionError.moveFailed(error.localizedDescription)))
            return
        }

        log("[root] download complete, extracting ...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try self.extractAndInstall(zipPath: tempZip)
                try? fm.removeItem(at: tempZip)
                self.finish(.success(()))
            } catch {
                try? fm.removeItem(at: tempZip)
                self.finish(.failure(error))
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        DispatchQueue.main.async { [completion] in
            completion(result)
        }
    }

    private func extractAndInstall(zipPath: URL) throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let finalRoot = documents.appendingPathComponent("root")
        let stagingRoot = documents.appendingPathComponent("root.download-\(UUID().uuidString)")

        try ZipExtractor.extract(
            zipFileURL: zipPath,
            strippingComponents: 1,
            into: stagingRoot,
            progress: { [weak self] message in self?.log(message) })

        let fm = FileManager.default
        if fm.fileExists(atPath: finalRoot.path) {
            try fm.removeItem(at: finalRoot)
        }
        try fm.moveItem(at: stagingRoot, to: finalRoot)
        log("[root] emulation root installed at \(finalRoot.path)")
    }
}
