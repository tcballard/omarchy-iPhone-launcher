// Copyright 2026 Tom Ballard. MIT License.
import Foundation

#if canImport(ObjectiveC)
@objc protocol OmarchyJITProtocol {
    func perform(_ request: Data, completion: @escaping (Data) -> Void)
}

@objc protocol OmarchyJITProgressProtocol {
    func reportProgress(_ message: String)
}
#endif

struct OmarchyJITRequest: Codable {
    enum Operation: String, Codable { case prepare, enable, reset }
    var operation: Operation
    var targetPID: Int32
    var pairing: Data
}

struct OmarchyJITReply: Codable {
    var error: String?
}

enum OmarchyAccelerationError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}
