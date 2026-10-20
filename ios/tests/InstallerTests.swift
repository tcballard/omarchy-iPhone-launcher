import Foundation
import CryptoKit

@main
struct InstallerTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "InstallerTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func payload(bytes: Data, partHash: String? = nil, wholeHash: String? = nil) throws -> OmarchyPayload {
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let config: [String: Any] = ["Information": ["UUID": "old", "Name": "iPhomarchy"],
                                   "Drive": [["Identifier": "old"]], "Network": [["MacAddress": "old"]]]
        let encoded = try PropertyListSerialization.data(fromPropertyList: config, format: .xml, options: 0).base64EncodedString()
        return OmarchyPayload(version: 1, imageBytes: Int64(bytes.count), imageSHA256: wholeHash ?? hash,
                              configBase64: encoded, parts: [.init(
                                url: URL(string: "https://github.com/tcballard/omarchy-iPhone-launcher/releases/download/test/part")!,
                                bytes: Int64(bytes.count), sha256: partHash ?? hash)])
    }

    static func installFixture(_ payload: OmarchyPayload, bytes: Data, documents: URL) async throws {
        let installer = OmarchyInstaller(download: { url, _ in
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try bytes.write(to: temp)
            return (temp, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        try await installer.install(payload, documents: documents) { _, _ in }
    }

    static func main() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? files.removeItem(at: root) }
        let bytes = Data("A verified disk fixture".utf8)
        let valid = try payload(bytes: bytes)
        try valid.validate()
        let docs = root.appendingPathComponent("success/Documents", isDirectory: true)
        try await installFixture(valid, bytes: bytes, documents: docs)
        let disk = docs.appendingPathComponent("iPhomarchy.utm/Data/omarchy.qcow2")
        let installed = try Data(contentsOf: disk)
        try check(installed == bytes, "Installed bytes changed")
        do {
            try await installFixture(valid, bytes: bytes, documents: docs)
            throw NSError(domain: "Existing disk was overwritten", code: 1)
        } catch OmarchyInstallError.alreadyInstalled {}
        try check(tryData(disk) == bytes, "Existing disk changed")

        for (index, bad) in [
            try payload(bytes: bytes, partHash: String(repeating: "0", count: 64)),
            try payload(bytes: bytes, wholeHash: String(repeating: "0", count: 64))
        ].enumerated() {
            let badDocs = root.appendingPathComponent("bad\(index)/Documents", isDirectory: true)
            do {
                try await installFixture(bad, bytes: bytes, documents: badDocs)
                throw NSError(domain: "Corrupt disk was accepted", code: 1)
            } catch OmarchyInstallError.integrity {}
            try check(!files.fileExists(atPath: badDocs.appendingPathComponent("iPhomarchy.utm").path), "Corrupt VM became visible")
            try check(!files.fileExists(atPath: badDocs.deletingLastPathComponent().appendingPathComponent("Library/OmarchySetup").path), "Partial data was not cleaned up")
        }
        let configA = try OmarchyInstaller.personalizedConfig(valid.configBase64)
        let configB = try OmarchyInstaller.personalizedConfig(valid.configBase64)
        try check(configA != configB, "Device identities were reused")
        let invalid = OmarchyPayload(version: 1, imageBytes: 1, imageSHA256: String(repeating: "0", count: 64),
                                     configBase64: valid.configBase64, parts: [.init(url: URL(string: "http://evil.example/part")!, bytes: 1, sha256: String(repeating: "0", count: 64))])
        do { try invalid.validate(); throw NSError(domain: "Invalid URL accepted", code: 1) }
        catch OmarchyInstallError.invalidManifest {}
        print("Installer: success, overwrite protection, part/full integrity, cleanup, identity and URL validation passed.")
    }

    static func tryData(_ url: URL) -> Data? { try? Data(contentsOf: url) }
}
