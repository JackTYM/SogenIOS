import Foundation
import Compression

enum ZipExtractorError: Error, CustomStringConvertible {
    case eocdNotFound
    case invalidCentralDirectoryEntry
    case invalidLocalFileHeader
    case shortRead(String)
    case unsupportedCompressionMethod(UInt16)
    case decompressionFailed(String)
    case sizeMismatch(String)

    var description: String {
        switch self {
        case .eocdNotFound:
            return "end-of-central-directory record not found"
        case .invalidCentralDirectoryEntry:
            return "invalid central directory entry"
        case .invalidLocalFileHeader:
            return "invalid local file header"
        case .shortRead(let what):
            return "short read while reading \(what)"
        case .unsupportedCompressionMethod(let method):
            return "unsupported zip compression method \(method)"
        case .decompressionFailed(let reason):
            return "decompression failed: \(reason)"
        case .sizeMismatch(let path):
            return "decompressed size mismatch for \(path)"
        }
    }
}

// A minimal ZIP reader covering exactly what root.zip needs: a central directory, stored (0)
// and deflated (8) entries, no ZIP64 (root.zip is ~155MiB compressed, well under the 4GiB
// classic-ZIP limit). Apple's Compression framework has no public unzip API, hence this file.
enum ZipExtractor {
    private struct CentralDirectoryEntry {
        let compressionMethod: UInt16
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let localHeaderOffset: UInt64
        let name: String
    }

    static func extract(
        zipFileURL: URL,
        strippingComponents: Int,
        into destinationRoot: URL,
        progress: ((String) -> Void)? = nil
    ) throws {
        let fm = FileManager.default
        let attrs = try fm.attributesOfItem(atPath: zipFileURL.path)
        guard let fileSize = (attrs[.size] as? NSNumber)?.uint64Value else {
            throw ZipExtractorError.eocdNotFound
        }

        let handle = try FileHandle(forReadingFrom: zipFileURL)
        defer { try? handle.close() }

        let entries = try readCentralDirectory(handle: handle, fileSize: fileSize)
        try fm.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        let total = entries.count
        var processed = 0
        var lastLoggedBucket = -1

        for entry in entries {
            processed += 1

            let strippedPath = stripComponents(entry.name, count: strippingComponents)
            if strippedPath.isEmpty {
                continue
            }

            let destURL = destinationRoot.appendingPathComponent(strippedPath)

            if entry.name.hasSuffix("/") {
                try fm.createDirectory(at: destURL, withIntermediateDirectories: true)
                continue
            }

            try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            let dataOffset = try localFileDataOffset(handle: handle, localHeaderOffset: entry.localHeaderOffset)
            try handle.seek(toOffset: dataOffset)
            let compressed = try readExact(handle: handle, count: Int(entry.compressedSize), what: strippedPath)

            let output: Data
            switch entry.compressionMethod {
            case 0:
                output = compressed
            case 8:
                output = try inflateRaw(compressed, expectedSize: Int(entry.uncompressedSize))
            default:
                throw ZipExtractorError.unsupportedCompressionMethod(entry.compressionMethod)
            }

            guard UInt64(output.count) == entry.uncompressedSize else {
                throw ZipExtractorError.sizeMismatch(strippedPath)
            }

            try output.write(to: destURL)

            if total > 0 {
                let bucket = ((processed * 100 / total) / 5) * 5
                if bucket != lastLoggedBucket {
                    lastLoggedBucket = bucket
                    progress?("[root] extracting ... \(bucket)% (\(processed)/\(total) files)")
                }
            }
        }
    }

    private static func stripComponents(_ path: String, count: Int) -> String {
        guard count > 0 else { return path }
        var parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if parts.count <= count {
            return ""
        }
        parts.removeFirst(count)
        return parts.joined(separator: "/")
    }

    private static func readExact(handle: FileHandle, count: Int, what: String) throws -> Data {
        guard count > 0 else { return Data() }
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            guard let chunk = try handle.read(upToCount: count - result.count), !chunk.isEmpty else {
                throw ZipExtractorError.shortRead(what)
            }
            result.append(chunk)
        }
        return result
    }

    private static func readCentralDirectory(handle: FileHandle, fileSize: UInt64) throws -> [CentralDirectoryEntry] {
        let maxEOCDSize: UInt64 = 65535 + 22
        let searchSize = min(fileSize, maxEOCDSize)
        try handle.seek(toOffset: fileSize - searchSize)
        let tail = try readExact(handle: handle, count: Int(searchSize), what: "end-of-central-directory search window")

        guard let eocdOffset = findEOCDSignature(in: tail) else {
            throw ZipExtractorError.eocdNotFound
        }
        guard eocdOffset + 22 <= tail.count else {
            throw ZipExtractorError.eocdNotFound
        }
        let eocd = tail.subdata(in: eocdOffset..<(eocdOffset + 22))

        let centralDirSize = eocd.readUInt32(at: 12)
        let centralDirOffset = eocd.readUInt32(at: 16)

        try handle.seek(toOffset: UInt64(centralDirOffset))
        let cdData = try readExact(handle: handle, count: Int(centralDirSize), what: "central directory")

        var entries: [CentralDirectoryEntry] = []
        var cursor = 0
        while cursor + 46 <= cdData.count {
            guard cdData.readUInt32(at: cursor) == 0x0201_4b50 else {
                throw ZipExtractorError.invalidCentralDirectoryEntry
            }

            let compressionMethod = cdData.readUInt16(at: cursor + 10)
            let compressedSize = cdData.readUInt32(at: cursor + 20)
            let uncompressedSize = cdData.readUInt32(at: cursor + 24)
            let nameLength = Int(cdData.readUInt16(at: cursor + 28))
            let extraLength = Int(cdData.readUInt16(at: cursor + 30))
            let commentLength = Int(cdData.readUInt16(at: cursor + 32))
            let localHeaderOffset = cdData.readUInt32(at: cursor + 42)

            let nameStart = cursor + 46
            guard nameStart + nameLength <= cdData.count else {
                throw ZipExtractorError.invalidCentralDirectoryEntry
            }
            guard let name = String(data: cdData.subdata(in: nameStart..<(nameStart + nameLength)), encoding: .utf8) else {
                throw ZipExtractorError.invalidCentralDirectoryEntry
            }

            entries.append(CentralDirectoryEntry(
                compressionMethod: compressionMethod,
                compressedSize: UInt64(compressedSize),
                uncompressedSize: UInt64(uncompressedSize),
                localHeaderOffset: UInt64(localHeaderOffset),
                name: name))

            cursor = nameStart + nameLength + extraLength + commentLength
        }

        return entries
    }

    private static func findEOCDSignature(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let base = data.startIndex
        var i = data.count - 22
        while i >= 0 {
            if data[base + i] == 0x50, data[base + i + 1] == 0x4b,
               data[base + i + 2] == 0x05, data[base + i + 3] == 0x06 {
                return i
            }
            i -= 1
        }
        return nil
    }

    private static func localFileDataOffset(handle: FileHandle, localHeaderOffset: UInt64) throws -> UInt64 {
        try handle.seek(toOffset: localHeaderOffset)
        let header = try readExact(handle: handle, count: 30, what: "local file header")
        guard header.readUInt32(at: 0) == 0x0403_4b50 else {
            throw ZipExtractorError.invalidLocalFileHeader
        }
        let nameLength = Int(header.readUInt16(at: 26))
        let extraLength = Int(header.readUInt16(at: 28))
        return localHeaderOffset + 30 + UInt64(nameLength) + UInt64(extraLength)
    }

    // ZIP's deflate entries store raw DEFLATE data with no zlib wrapper. Despite its name,
    // Apple's Compression framework decodes exactly that under COMPRESSION_ZLIB -- it is not
    // zlib-container-aware, it's raw DEFLATE. Using COMPRESSION_ZLIB here is deliberate, not a
    // copy-paste mistake.
    private static func inflateRaw(_ input: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }

        var output = Data(count: expectedSize)
        let written: Int = try output.withUnsafeMutableBytes { outRaw in
            try input.withUnsafeBytes { inRaw in
                guard let outBase = outRaw.bindMemory(to: UInt8.self).baseAddress else {
                    throw ZipExtractorError.decompressionFailed("nil output buffer")
                }
                guard let inBase = inRaw.bindMemory(to: UInt8.self).baseAddress else {
                    throw ZipExtractorError.decompressionFailed("nil input buffer")
                }
                let result = compression_decode_buffer(
                    outBase, expectedSize, inBase, input.count, nil, COMPRESSION_ZLIB)
                if result == 0 {
                    throw ZipExtractorError.decompressionFailed("compression_decode_buffer returned 0")
                }
                return result
            }
        }

        if written != expectedSize {
            output.removeSubrange(written..<output.count)
        }
        return output
    }
}

private extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        let base = startIndex + offset
        return UInt16(self[base]) | (UInt16(self[base + 1]) << 8)
    }

    func readUInt32(at offset: Int) -> UInt32 {
        let base = startIndex + offset
        return UInt32(self[base])
            | (UInt32(self[base + 1]) << 8)
            | (UInt32(self[base + 2]) << 16)
            | (UInt32(self[base + 3]) << 24)
    }
}
