// Copyright 2026 Tom Ballard. MIT License.
import SwiftUI
import Combine

@MainActor
final class OmarchyAcceleration: ObservableObject {
    static let shared = OmarchyAcceleration()
    let pairing = OmarchyDevicePairing()
    let tunnel = OmarchyLocalTunnel()
    @Published private(set) var isBusy = false
    @Published private(set) var status = "Set up acceleration before your first start."
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?
    private var attemptedVM = false
    private var pairingObservation: AnyCancellable?

    private init() {
        pairingObservation = pairing.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    private func preflight() throws -> Data {
        guard omarchy_development_signed() else {
            throw OmarchyAccelerationError.message("Install the development-signed edition of iPhomarchy. This build does not allow the debugger to attach.")
        }
        guard !pairing.isPairing else { throw OmarchyAccelerationError.message("Finish pairing this iPhone first.") }
        do { return try OmarchyPairingStore.load() }
        catch { throw OmarchyAccelerationError.message("Pair this iPhone in acceleration setup, or import its remote pairing file.") }
    }

    func checkSetup() {
        run {
            let pairing = try self.preflight()
            try await self.tunnel.connect()
            let helper = try await self.helper()
            defer { helper.invalidate() }
            try await helper.perform(OmarchyJITRequest(operation: .prepare, targetPID: getpid(), pairing: pairing))
            self.status = "Setup checked. Start Omarchy to activate acceleration."
        }
    }

    func resetDeveloperSupport() {
        run {
            let helper = try await self.helper()
            defer { helper.invalidate() }
            try await helper.perform(OmarchyJITRequest(operation: .reset, targetPID: getpid(), pairing: Data()))
            self.status = "Developer support cleared. Check setup to download it again."
        }
    }

    func start(machine: VMData, data: UTMData) {
        guard !isBusy else { return }
        if !machine.isStopped { data.run(vm: machine); return }
        run {
            guard !self.attemptedVM else {
                throw OmarchyAccelerationError.message("Quit and reopen iPhomarchy before starting the desktop again. The emulator can start once per app session.")
            }
            let pairing = try self.preflight()
            try OmarchyVMPaths.relocateDiagnosticPaths(at: machine.pathUrl)
            try machine.load()
            try machine.wrapped?.reload(from: nil)
            try await self.tunnel.connect()
            let helper = try await self.helper()
            defer { helper.invalidate() }
            try await helper.perform(OmarchyJITRequest(operation: .prepare, targetPID: getpid(), pairing: pairing))
            guard !omarchy_debugger_attached() else {
                throw OmarchyAccelerationError.message("Another debugger is already attached. Disconnect it and reopen iPhomarchy to use the bundled helper.")
            }
            self.status = "Attaching the acceleration helper…"
            var outcome: Result<Void, Error>?
            let activation = Task { @MainActor in
                do {
                    try await helper.perform(OmarchyJITRequest(operation: .enable, targetPID: getpid(), pairing: pairing))
                    outcome = .success(())
                } catch { outcome = .failure(error) }
            }
            defer { activation.cancel() }
            try await OmarchyJITLaunchGate.waitForDebugger(attached: { omarchy_debugger_attached() }, completed: { outcome })
            try Task.checkCancellation()
            Main.jitAvailable = true
            self.status = "Preparing accelerated memory and starting Omarchy…"
            self.attemptedVM = true
            data.run(vm: machine)
            await activation.value
            do {
                guard let outcome else { throw OmarchyAccelerationError.message("Acceleration did not return a result.") }
                try outcome.get()
            } catch {
                data.stop(vm: machine)
                data.showErrorAlert(message: "Acceleration failed: " + error.localizedDescription)
                throw error
            }
            self.status = "Acceleration is active for this app session."
        }
    }

    private func helper() async throws -> OmarchyJITConnection {
        try await OmarchyJITConnection.launch { [weak self] message in self?.status = message }
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard task == nil else { return }
        error = nil
        isBusy = true
        UIApplication.shared.isIdleTimerDisabled = true
        task = Task {
            defer {
                isBusy = false
                task = nil
                UIApplication.shared.isIdleTimerDisabled = false
            }
            do { try await operation() }
            catch is CancellationError { status = "Acceleration cancelled." }
            catch { self.error = error.localizedDescription; status = "Acceleration needs attention." }
        }
    }
}
