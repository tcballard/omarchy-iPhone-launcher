// Copyright 2026 Tom Ballard. MIT License.
import Foundation

enum OmarchyPairingFile {
    static let maximumBytes = 2_000_000

    static func read(_ url: URL) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: maximumBytes + 1) ?? Data()
        guard !data.isEmpty, data.count <= maximumBytes else {
            throw OmarchyAccelerationError.message("Choose a pairing plist smaller than 2 MB.")
        }
        return data
    }
}
