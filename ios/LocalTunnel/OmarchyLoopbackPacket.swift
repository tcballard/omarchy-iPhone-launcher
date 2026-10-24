// Copyright 2026 Tom Ballard. MIT License.
import Foundation

enum OmarchyLoopbackPacket {
    static let address = "10.7.1.1"
    static let peer = "10.7.0.1"

    static func reflected(_ packet: Data) -> Data? {
        var bytes = Array(packet)
        guard bytes.count >= 20, bytes[0] >> 4 == 4 else { return nil }
        let headerLength = Int(bytes[0] & 15) * 4
        let totalLength = Int(bytes[2]) * 256 + Int(bytes[3])
        guard headerLength >= 20, headerLength <= totalLength, totalLength == bytes.count,
              Array(bytes[12..<16]) == [10, 7, 1, 1],
              Array(bytes[16..<20]) == [10, 7, 0, 1] else { return nil }
        // IPv4 and transport pseudo-header checksums are unchanged by swapping
        // the source and destination addresses (the same words are summed).
        for index in 0..<4 { bytes.swapAt(12 + index, 16 + index) }
        return Data(bytes)
    }
}
