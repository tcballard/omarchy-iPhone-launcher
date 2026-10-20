// Copyright 2026 Tom Ballard. Licensed under the MIT License.
import Foundation
import CryptoKit

struct OmarchyPayload: Codable {
    struct Part: Codable {
        let url: URL
        let bytes: Int64
        let sha256: String
    }

    let version: Int
    let imageBytes: Int64
    let imageSHA256: String
    let configBase64: String
    let parts: [Part]

    func validate() throws {
        let hashPattern = "^[0-9a-f]{64}$"
        guard version == 1, imageBytes > 0, imageBytes <= 32 * 1_073_741_824,
              !parts.isEmpty, parts.count <= 32,
              imageSHA256.range(of: hashPattern, options: .regularExpression) != nil,
              Data(base64Encoded: configBase64) != nil else {
            throw OmarchyInstallError.invalidManifest
        }
        var total: Int64 = 0
        for part in parts {
            guard part.bytes > 0, part.bytes <= 1_073_741_824,
                  part.url.scheme == "https", part.url.host == "github.com",
                  part.url.path.hasPrefix("/tcballard/omarchy-iPhone-launcher/releases/download/"),
                  part.sha256.range(of: hashPattern, options: .regularExpression) != nil else {
                throw OmarchyInstallError.invalidManifest
            }
            total += part.bytes
        }
        guard total == imageBytes else { throw OmarchyInstallError.invalidManifest }
    }
}

enum OmarchyInstallError: LocalizedError {
    case invalidManifest, integrity, alreadyInstalled, insufficientSpace(Int64), http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidManifest: return "This build has an invalid Omarchy download manifest. Install a newer build."
        case .integrity: return "The download failed its integrity check. Retry to download a fresh copy."
        case .alreadyInstalled: return "Omarchy already exists on this phone. Your existing files have been kept."
        case .insufficientSpace(let bytes):
            return "Setup needs at least \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) free. Free some storage and retry."
        case .http(let status): return "The image server returned HTTP \(status). Check your connection and retry."
        }
    }
}

private final class OmarchyDownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let update: @Sendable (Double) -> Void
    init(update: @escaping @Sendable (Double) -> Void) { self.update = update }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            update(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}

/// Performs file work off the main actor; the final bundle appears only after verification.
actor OmarchyInstaller {
    typealias Progress = @Sendable (Double, String) -> Void
    typealias Download = @Sendable (URL, URLSessionTaskDelegate) async throws -> (URL, URLResponse)
    private let download: Download

    init(download: @escaping Download = { url, delegate in
        try await URLSession.shared.download(from: url, delegate: delegate)
    }) {
        self.download = download
    }

    func install(_ payload: OmarchyPayload, documents: URL, progress: @escaping Progress) async throws {
        try payload.validate()
        let files = FileManager.default
        let destination = documents.appendingPathComponent("iPhomarchy.utm", isDirectory: true)
        guard !files.fileExists(atPath: destination.path) else { throw OmarchyInstallError.alreadyInstalled }
        try files.createDirectory(at: documents, withIntermediateDirectories: true)
        let workRoot = documents.deletingLastPathComponent().appendingPathComponent("Library/OmarchySetup", isDirectory: true)
        // The app owns this directory. A killed setup can leave a partial disk here.
        if files.fileExists(atPath: workRoot.path) { try files.removeItem(at: workRoot) }
        let required = payload.imageBytes + (payload.parts.map(\.bytes).max() ?? 0) + 2 * 1_073_741_824
        let available = try documents.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        if let available = available, available < required {
            throw OmarchyInstallError.insufficientSpace(required)
        }
        let staging = workRoot.appendingPathComponent("iPhomarchy.utm", isDirectory: true)
        let disk = staging.appendingPathComponent("Data/omarchy.qcow2")
        try files.createDirectory(at: disk.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? files.removeItem(at: workRoot) }
        guard files.createFile(atPath: disk.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let output = try FileHandle(forWritingTo: disk)
        defer { try? output.close() }
        var wholeHash = SHA256()
        var completed: Int64 = 0
        for (index, part) in payload.parts.enumerated() {
            try Task.checkCancellation()
            let base = completed
            let label = "Downloading Omarchy · \(index + 1) of \(payload.parts.count)"
            let delegate = OmarchyDownloadProgress { fraction in
                progress((Double(base) + fraction * Double(part.bytes)) / Double(payload.imageBytes), label)
            }
            let (temporary, response) = try await download(part.url, delegate)
            defer { try? files.removeItem(at: temporary) }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw OmarchyInstallError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            progress(Double(completed) / Double(payload.imageBytes), "Checking download \(index + 1)…")
            let attributes = try files.attributesOfItem(atPath: temporary.path)
            guard (attributes[.size] as? NSNumber)?.int64Value == part.bytes else {
                throw OmarchyInstallError.integrity
            }
            let input = try FileHandle(forReadingFrom: temporary)
            defer { try? input.close() }
            var partHash = SHA256()
            while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
                try Task.checkCancellation()
                partHash.update(data: chunk)
                wholeHash.update(data: chunk)
                try output.write(contentsOf: chunk)
            }
            guard Self.hex(partHash.finalize()) == part.sha256 else { throw OmarchyInstallError.integrity }
            completed += part.bytes
        }
        try output.synchronize()
        try output.close()
        guard Self.hex(wholeHash.finalize()) == payload.imageSHA256 else { throw OmarchyInstallError.integrity }
        try Task.checkCancellation()
        progress(1, "Preparing your Omarchy desktop…")
        let config = try Self.personalizedConfig(payload.configBase64)
        try config.write(to: staging.appendingPathComponent("config.plist"), options: .atomic)
        try JSONEncoder().encode(payload).write(to: staging.appendingPathComponent("provenance.json"), options: .atomic)
        try files.moveItem(at: staging, to: destination)
    }

    static func personalizedConfig(_ base64: String) throws -> Data {
        guard let data = Data(base64Encoded: base64),
              var config = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              var info = config["Information"] as? [String: Any],
              var drives = config["Drive"] as? [[String: Any]], !drives.isEmpty,
              var networks = config["Network"] as? [[String: Any]], !networks.isEmpty else {
            throw OmarchyInstallError.invalidManifest
        }
        info["UUID"] = UUID().uuidString
        config["Information"] = info
        drives[0]["Identifier"] = UUID().uuidString
        config["Drive"] = drives
        let mac = [UInt8(0x02)] + (0..<5).map { _ in UInt8.random(in: 0...255) }
        networks[0]["MacAddress"] = mac.map { String(format: "%02x", $0) }.joined(separator: ":")
        config["Network"] = networks
        return try PropertyListSerialization.data(fromPropertyList: config, format: .xml, options: 0)
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
