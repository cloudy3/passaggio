import Foundation

/// Minimal POSIX ustar writer/reader for the backup file.
///
/// Why tar rather than zip: the backup is mostly already-compressed audio, so
/// compression buys nothing; tar streams file-by-file with constant memory, has no
/// 4 GB central-directory limit to work around, and is about 150 lines with no
/// dependency. Only regular files are supported, which is all a backup contains.
public enum TarArchive {
    public enum Error: Swift.Error, LocalizedError, Equatable {
        case pathTooLong(String)
        case unsafePath(String)
        case corruptHeader
        case truncated
        case fileTooLarge(String)

        public var errorDescription: String? {
            switch self {
            case .pathTooLong(let path): "Path too long for the archive: \(path)"
            case .unsafePath(let path): "The backup contains an unsafe path: \(path)"
            case .corruptHeader: "The backup file is damaged (bad header)."
            case .truncated: "The backup file is incomplete."
            case .fileTooLarge(let path): "File too large for the archive: \(path)"
            }
        }
    }

    static let blockSize = 512
    static let copyChunk = 1 << 20
    static let maxSize: UInt64 = 0o77777777777 // 11 octal digits, just under 8 GiB

    // MARK: Writing

    /// Writes `entries` (archive path → source file) to `destination`.
    public static func write(entries: [(path: String, source: URL)], to destination: URL) throws {
        _ = FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        for entry in entries {
            try validate(path: entry.path)
            let attributes = try FileManager.default.attributesOfItem(atPath: entry.source.path)
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            guard size <= maxSize else { throw Error.fileTooLarge(entry.path) }
            let modified = (attributes[.modificationDate] as? Date) ?? Date()

            try output.write(contentsOf: header(path: entry.path, size: size, modified: modified))

            let input = try FileHandle(forReadingFrom: entry.source)
            defer { try? input.close() }
            var written: UInt64 = 0
            while let chunk = try input.read(upToCount: copyChunk), !chunk.isEmpty {
                try output.write(contentsOf: chunk)
                written += UInt64(chunk.count)
            }
            guard written == size else { throw Error.truncated }
            try output.write(contentsOf: Data(count: padding(for: size)))
        }
        // End of archive: two zero blocks.
        try output.write(contentsOf: Data(count: blockSize * 2))
    }

    static func header(path: String, size: UInt64, modified: Date) throws -> Data {
        var block = [UInt8](repeating: 0, count: blockSize)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count <= 100 else { throw Error.pathTooLong(path) }

        func put(_ bytes: [UInt8], at offset: Int) {
            for (i, byte) in bytes.enumerated() { block[offset + i] = byte }
        }
        func octal(_ value: UInt64, width: Int) -> [UInt8] {
            // width-1 digits, zero-padded, NUL-terminated.
            let digits = String(value, radix: 8)
            return Array((String(repeating: "0", count: max(0, width - 1 - digits.count)) + digits).utf8) + [0]
        }

        put(pathBytes, at: 0)
        put(octal(0o644, width: 8), at: 100)                       // mode
        put(octal(0, width: 8), at: 108)                           // uid
        put(octal(0, width: 8), at: 116)                           // gid
        put(octal(size, width: 12), at: 124)                       // size
        put(octal(UInt64(max(0, modified.timeIntervalSince1970)), width: 12), at: 136) // mtime
        put(Array("        ".utf8), at: 148)                       // checksum placeholder
        block[156] = UInt8(ascii: "0")                             // regular file
        put(Array("ustar".utf8) + [0], at: 257)                    // magic
        put(Array("00".utf8), at: 263)                             // version

        let checksum = block.reduce(0) { $0 + UInt64($1) }
        let digits = String(checksum, radix: 8)
        put(Array((String(repeating: "0", count: max(0, 6 - digits.count)) + digits).utf8) + [0, 0x20], at: 148)
        return Data(block)
    }

    static func padding(for size: UInt64) -> Int {
        let remainder = Int(size % UInt64(blockSize))
        return remainder == 0 ? 0 : blockSize - remainder
    }

    static func validate(path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              !components.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else {
            throw Error.unsafePath(path)
        }
    }

    // MARK: Reading

    /// Extracts every regular file into `directory` and returns the archive paths.
    @discardableResult
    public static func extract(from archive: URL, into directory: URL) throws -> [String] {
        let input = try FileHandle(forReadingFrom: archive)
        defer { try? input.close() }
        var extracted: [String] = []

        while true {
            guard let block = try input.read(upToCount: blockSize), block.count == blockSize else {
                throw Error.truncated
            }
            if block.allSatisfy({ $0 == 0 }) { break } // end-of-archive marker

            let bytes = [UInt8](block)
            guard verifyChecksum(bytes) else { throw Error.corruptHeader }
            let path = string(bytes[0..<100])
            let prefix = string(bytes[345..<500])
            let fullPath = prefix.isEmpty ? path : prefix + "/" + path
            guard let size = parseOctal(bytes[124..<136]) else { throw Error.corruptHeader }
            let type = bytes[156]

            let isRegularFile = type == UInt8(ascii: "0") || type == 0
            if isRegularFile {
                try validate(path: fullPath)
                let target = directory.appendingPathComponent(fullPath)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                _ = FileManager.default.createFile(atPath: target.path, contents: nil)
                let output = try FileHandle(forWritingTo: target)
                defer { try? output.close() }
                try copy(size, from: input, to: output)
                extracted.append(fullPath)
            } else {
                try skip(size, in: input)
            }
            try skip(UInt64(padding(for: size)), in: input)
        }
        return extracted
    }

    static func copy(_ count: UInt64, from input: FileHandle, to output: FileHandle) throws {
        var remaining = count
        while remaining > 0 {
            let want = Int(min(UInt64(copyChunk), remaining))
            guard let chunk = try input.read(upToCount: want), !chunk.isEmpty else { throw Error.truncated }
            try output.write(contentsOf: chunk)
            remaining -= UInt64(chunk.count)
        }
    }

    static func skip(_ count: UInt64, in input: FileHandle) throws {
        guard count > 0 else { return }
        let target = try input.offset() + count
        try input.seek(toOffset: target)
    }

    static func verifyChecksum(_ bytes: [UInt8]) -> Bool {
        guard let stored = parseOctal(bytes[148..<156]) else { return false }
        var sum: UInt64 = 0
        for (i, byte) in bytes.enumerated() {
            sum += (148..<156).contains(i) ? 0x20 : UInt64(byte)
        }
        return sum == stored
    }

    static func parseOctal(_ bytes: ArraySlice<UInt8>) -> UInt64? {
        let text = String(decoding: bytes.drop { $0 == 0x20 }.prefix { $0 != 0 && $0 != 0x20 }, as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return 0 }
        return UInt64(text, radix: 8)
    }

    static func string(_ bytes: ArraySlice<UInt8>) -> String {
        String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}
