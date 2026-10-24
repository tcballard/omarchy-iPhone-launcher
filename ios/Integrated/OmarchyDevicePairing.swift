// Copyright 2026 Tom Ballard. MIT License.
import UIKit
import BackgroundTasks

@MainActor
final class OmarchyDevicePairing: NSObject, ObservableObject, NetServiceDelegate {
    @Published private(set) var isPairing = false
    @Published private(set) var isPaired = OmarchyPairingStore.isAvailable
    @Published private(set) var code: String?
    @Published private(set) var status = ""
    @Published private(set) var error: String?
    private var handle: UInt64 = 0
    private var service: NetService?
    private var pollTask: Task<Void, Never>?
    private var grace: UIBackgroundTaskIdentifier = .invalid
    private var continued: BGContinuedProcessingTask?
    private var requestIdentifier: String { Bundle.main.bundleIdentifier! + ".pairing.session" }
    private var registered = false

    private struct PairingStatus: Decodable {
        var phase: String
        var port: UInt16
        var service: String
        var txt: [String: String]
        var code: String?
        var error: String?
    }

    func start() {
        guard !isPairing else { return }
        guard #available(iOS 27, *) else {
            error = "Pairing on this device requires iOS 27. Import a remote pairing file created on your computer instead."
            return
        }
        do {
            try OmarchyPairingStore.prepareDirectory()
            error = nil
            code = nil
            status = "Starting pairing…"
            // Fresh signing keys need a fresh host identity; reusing an old
            // identity could make iOS attempt pair-verify against its old key.
            let identity = UUID().uuidString
            handle = omarchy_pair_start("iPhomarchy", "iPhomarchy-" + identity, OmarchyPairingStore.url.path)
            guard handle != 0 else { throw OmarchyAccelerationError.message("The pairing service could not start. Please retry.") }
            isPairing = true
            beginBackgroundWork()
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, self.handle != 0 else { return }
                    do { try self.poll() }
                    catch { self.fail(error.localizedDescription); return }
                    if !self.isPairing { return }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        } catch { fail(error.localizedDescription) }
    }

    func importFile(_ url: URL) {
        guard !isPairing else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try OmarchyPairingStore.save(OmarchyPairingFile.read(url))
            isPaired = true
            status = "Pairing file imported."
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func cancel() {
        status = "Pairing cancelled."
        finish(success: false)
    }

    func importFailed(_ failure: Error) {
        if let failure = failure as? CocoaError, failure.code == .userCancelled { return }
        error = failure.localizedDescription
    }

    private func poll() throws {
        guard let result = omarchy_pair_status(handle) else {
            throw OmarchyAccelerationError.message("The pairing service stopped. Please retry.")
        }
        defer { omarchy_pair_free_string(result) }
        let state = try JSONDecoder().decode(PairingStatus.self, from: Data(String(cString: result).utf8))
        if state.port != 0 && service == nil {
            let service = NetService(domain: "local.", type: "_remotepairing-pairable-host._tcp.", name: state.service, port: Int32(state.port))
            service.delegate = self
            service.setTXTRecord(NetService.data(fromTXTRecord: state.txt.mapValues { Data($0.utf8) }))
            self.service = service
            service.publish()
        }
        switch state.phase {
        case "waiting":
            status = "Open Settings → Privacy & Security → Developer Mode. Select Pair with iPhomarchy."
        case "code":
            if code != state.code {
                code = state.code
                status = "Enter this code in the iOS pairing prompt."
                continued?.updateTitle("Pairing code: \(state.code ?? "")", subtitle: "Enter this code in Settings")
                continued?.progress.completedUnitCount = 1
            }
        case "complete":
            // Validate and apply iOS file protection before marking setup complete.
            try OmarchyPairingStore.save(OmarchyPairingStore.load())
            isPaired = true
            status = "This iPhone is paired."
            finish(success: true)
        case "failed": throw OmarchyAccelerationError.message(state.error ?? "Pairing failed. Please retry.")
        default: break
        }
    }

    nonisolated func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        Task { @MainActor [weak self] in
            self?.fail("Could not advertise pairing. Allow Local Network access for iPhomarchy in Settings, then retry. (\(errorDict[NetService.errorCode]?.intValue ?? 0))")
        }
    }

    private func beginBackgroundWork() {
        if !registered {
            registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: requestIdentifier, using: .main) { [weak self] task in
                guard let continued = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                Task { @MainActor in
                    guard let self, self.isPairing else { continued.setTaskCompleted(success: false); return }
                    self.continued = continued
                    continued.progress.totalUnitCount = 2
                    continued.expirationHandler = { [weak self] in
                        Task { @MainActor in self?.fail("iOS ended the pairing session. Return to iPhomarchy and pair again.") }
                    }
                    if let code = self.code {
                        continued.updateTitle("Pairing code: \(code)", subtitle: "Enter this code in Settings")
                        continued.progress.completedUnitCount = 1
                    }
                }
            }
        }
        grace = UIApplication.shared.beginBackgroundTask(withName: "Pair iPhomarchy") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.continued == nil { self.fail("iOS paused pairing. Start again and return to iPhomarchy to view the code.") }
                self.endGrace()
            }
        }
        guard registered else { return }
        let request = BGContinuedProcessingTaskRequest(identifier: requestIdentifier, title: "Pair iPhomarchy", subtitle: "Select iPhomarchy in Developer Mode settings")
        request.strategy = .fail
        do { try BGTaskScheduler.shared.submit(request) }
        catch { status = "Pairing is ready. Open Developer Mode settings, select iPhomarchy, then return here promptly to view the code." }
    }

    private func fail(_ message: String) {
        error = message
        finish(success: false)
    }

    private func endGrace() {
        if grace != .invalid { UIApplication.shared.endBackgroundTask(grace); grace = .invalid }
    }

    private func finish(success: Bool) {
        pollTask?.cancel()
        pollTask = nil
        if handle != 0 { omarchy_pair_cancel(handle); handle = 0 }
        service?.stop()
        service = nil
        if success { continued?.progress.completedUnitCount = 2 }
        continued?.setTaskCompleted(success: success)
        continued = nil
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: requestIdentifier)
        endGrace()
        code = nil
        isPairing = false
    }
}
