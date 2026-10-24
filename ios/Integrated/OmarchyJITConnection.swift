// Copyright 2026 Tom Ballard. MIT License.
import Foundation
import ExtensionFoundation

extension AppExtensionPoint {
    @Definition
    static var omarchyJIT: AppExtensionPoint {
        Name("omarchy-jit")
        UserInterface(false)
    }
}

// XPC failure, timeout and reply can race. Resume the awaiting task once.
private final class OmarchyJITCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }

    func finish(_ result: Result<Void, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

@MainActor
final class OmarchyJITConnection: NSObject, OmarchyJITProgressProtocol {
    private let connection: NSXPCConnection
    private let stopProcess: () -> Void
    private let progress: (String) -> Void
    private var pending: OmarchyJITCompletion?
    private var stopped = false

    private init(connection: NSXPCConnection, stop: @escaping () -> Void, progress: @escaping (String) -> Void) {
        self.connection = connection
        self.stopProcess = stop
        self.progress = progress
    }

    static func launch(progress: @escaping (String) -> Void) async throws -> OmarchyJITConnection {
        let monitor = try await AppExtensionPoint.Monitor(appExtensionPoint: .omarchyJIT)
        guard let identity = monitor.identities.first else {
            throw OmarchyAccelerationError.message("The bundled acceleration helper is missing. Reinstall the complete iPhomarchy app.")
        }
        let configuration = AppExtensionProcess.Configuration(appExtensionIdentity: identity) {}
        let process = try await AppExtensionProcess(configuration: configuration)
        let connection: NSXPCConnection
        do { connection = try process.makeXPCConnection() }
        catch { process.invalidate(); throw error }
        let helper = OmarchyJITConnection(connection: connection, stop: { process.invalidate() }, progress: progress)
        connection.remoteObjectInterface = NSXPCInterface(with: OmarchyJITProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: OmarchyJITProgressProtocol.self)
        connection.exportedObject = helper
        connection.resume()
        return helper
    }

    nonisolated func reportProgress(_ message: String) {
        Task { @MainActor [weak self] in
            guard let self, !self.stopped else { return }
            self.progress(message)
        }
    }

    func perform(_ request: OmarchyJITRequest) async throws {
        let encoded = try JSONEncoder().encode(request)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completion = OmarchyJITCompletion(continuation)
            pending = completion
            let lost: @Sendable () -> Void = {
                completion.finish(.failure(OmarchyAccelerationError.message("The acceleration helper disconnected. Return to the home screen and retry.")))
            }
            connection.interruptionHandler = lost
            connection.invalidationHandler = lost
            DispatchQueue.global().asyncAfter(deadline: .now() + 900) {
                completion.finish(.failure(OmarchyAccelerationError.message("Acceleration setup timed out. Check your pairing and local tunnel, then retry.")))
            }
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                completion.finish(.failure(error))
            }) as? OmarchyJITProtocol else {
                completion.finish(.failure(OmarchyAccelerationError.message("Cannot communicate with the acceleration helper.")))
                return
            }
            proxy.perform(encoded) { reply in
                do {
                    let result = try JSONDecoder().decode(OmarchyJITReply.self, from: reply)
                    if let error = result.error { throw OmarchyAccelerationError.message(error) }
                    completion.finish(.success(()))
                } catch { completion.finish(.failure(error)) }
            }
        }
    }

    func invalidate() {
        guard !stopped else { return }
        stopped = true
        pending?.finish(.failure(CancellationError()))
        pending = nil
        connection.exportedObject = nil
        connection.invalidate()
        stopProcess()
    }
}
