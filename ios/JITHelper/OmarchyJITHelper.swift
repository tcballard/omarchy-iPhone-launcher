// Copyright 2026 Tom Ballard. MIT License.
import Foundation
import ExtensionFoundation
import StikJIT

@main
final class OmarchyJITHelper: AppExtension {
    required init() {}

    @AppExtensionPoint.Bind
    var boundExtensionPoint: AppExtensionPoint {
        AppExtensionPoint.Identifier(host: "$(UTM_HOST_BUNDLE_IDENTIFIER)", name: "omarchy-jit")
    }

    var configuration: some AppExtensionConfiguration {
        ConnectionHandler { connection in
            connection.exportedInterface = NSXPCInterface(with: OmarchyJITProtocol.self)
            connection.exportedObject = OmarchyJITService(connection: connection)
            connection.remoteObjectInterface = NSXPCInterface(with: OmarchyJITProgressProtocol.self)
            connection.invalidationHandler = { _exit(0) }
            connection.resume()
            return true
        }
    }
}

private final class OmarchyJITService: NSObject, OmarchyJITProtocol {
    private let queue = DispatchQueue(label: "dev.tcballard.iphomarchy.jit", qos: .userInitiated)
    private weak var connection: NSXPCConnection?

    init(connection: NSXPCConnection) { self.connection = connection }

    func perform(_ encoded: Data, completion: @escaping (Data) -> Void) {
        queue.async { [self] in
            // An independent helper watchdog also runs while the app is stopped
            // at QEMU's allocation breakpoint. Losing the host cannot leak a debugger.
            let watchdog = DispatchWorkItem { _exit(124) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 900, execute: watchdog)
            defer { watchdog.cancel() }
            let reply: OmarchyJITReply
            do {
                let request = try JSONDecoder().decode(OmarchyJITRequest.self, from: encoded)
                let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                let cache = library.appendingPathComponent("StikJIT", isDirectory: true)
                try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                var cacheValues = URLResourceValues()
                cacheValues.isExcludedFromBackup = true
                var excludedCache = cache
                try excludedCache.setResourceValues(cacheValues)
                let paths = DDIPaths.default(in: cache)
                let pairing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".plist")
                try request.pairing.write(to: pairing, options: [.atomic, .completeFileProtection])
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pairing.path)
                defer { try? FileManager.default.removeItem(at: pairing) }
                switch request.operation {
                case .prepare:
                    switch StikJIT.prepareDevice(pairingFile: pairing, paths: paths, progress: stage) {
                    case .ready: break
                    case .unreachable(let reason), .preparationFailed(let reason):
                        throw OmarchyAccelerationError.message(reason)
                    }
                case .enable:
                    guard request.targetPID > 0 else { throw OmarchyAccelerationError.message("Invalid app process.") }
                    // This matches the BRK #0x69 allocation protocol in the pinned
                    // UTM/QEMU build. It must finish preparing the pages, not only attach.
                    try StikJIT.enableJIT(targetPID: request.targetPID, pairingFile: pairing, ddiPaths: paths,
                                          script: .legacy, forceScript: true,
                                          preparationProgress: stage, progress: report)
                case .reset:
                    try StikJIT.resetCachedDDI(at: paths)
                }
                reply = OmarchyJITReply(error: nil)
            } catch {
                reply = OmarchyJITReply(error: error.localizedDescription)
            }
            completion((try? JSONEncoder().encode(reply)) ?? Data("{\"error\":\"Invalid helper response\"}".utf8))
        }
    }

    private func report(_ message: String) {
        (connection?.remoteObjectProxy as? OmarchyJITProgressProtocol)?.reportProgress(message)
    }

    private func stage(_ stage: StikJIT.PreparationStage) {
        switch stage {
        case .checkingReachability: report("Connecting to this iPhone…")
        case .checkingDDI: report("Checking developer support…")
        case .downloadingDDI(let fraction, let status): report("Developer support: \(Int(fraction * 100))% — \(status)")
        case .mountingDDI(let fraction): report("Preparing developer support: \(Int(fraction * 100))%")
        case .verifyingDDI: report("Verifying developer support…")
        case .ready: report("Developer support is ready.")
        @unknown default: report("Preparing developer support…")
        }
    }
}
