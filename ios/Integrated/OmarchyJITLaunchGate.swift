// Copyright 2026 Tom Ballard. MIT License.
import Foundation

enum OmarchyJITLaunchGate {
    @MainActor
    static func waitForDebugger(timeout: TimeInterval = 45,
                                attached: () -> Bool,
                                completed: () -> Result<Void, Error>?) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !attached() {
            try Task.checkCancellation()
            if let result = completed() {
                try result.get()
                throw OmarchyAccelerationError.message("The helper finished without an attached debugger. Omarchy has not been started. Retry acceleration setup.")
            }
            guard Date() < deadline else {
                throw OmarchyAccelerationError.message("The debugger did not attach to iPhomarchy. Check Developer Mode and the pairing for this iPhone.")
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
