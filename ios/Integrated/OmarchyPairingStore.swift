// Copyright 2026 Tom Ballard. MIT License.
import Foundation
import CryptoKit

enum OmarchyPairingStore {
    static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StikJIT", isDirectory: true).appendingPathComponent("pairingFile.plist")
    }

    static func validated(_ bytes: Data) throws -> Data {
        guard bytes.count <= OmarchyPairingFile.maximumBytes,
              let record = try PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any],
              let privateKey = record["private_key"] as? Data, privateKey.count == 32,
              let publicKey = record["public_key"] as? Data, publicKey.count == 32,
              let identifier = record["identifier"] as? String, !identifier.isEmpty,
              let irk = record["alt_irk"] as? Data, irk.count == 16 else {
            throw OmarchyAccelerationError.message("Choose a remote pairing file for this iPhone. A USB-only pairing file does not contain the required remote pairing keys.")
        }
        let signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKey)
        guard signingKey.publicKey.rawRepresentation == publicKey else {
            throw OmarchyAccelerationError.message("The pairing file's keys do not match. Pair this iPhone again.")
        }
        return bytes
    }

    static func load() throws -> Data { try validated(OmarchyPairingFile.read(url)) }
    static var isAvailable: Bool { (try? load()) != nil }

    static func prepareDirectory() throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var excluded = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
    }

    static func save(_ bytes: Data) throws {
        let bytes = try validated(bytes)
        try prepareDirectory()
        try bytes.write(to: url, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
