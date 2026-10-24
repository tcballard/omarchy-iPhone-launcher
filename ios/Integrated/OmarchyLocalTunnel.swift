// Copyright 2026 Tom Ballard. MIT License.
import NetworkExtension

@MainActor
final class OmarchyLocalTunnel: ObservableObject {
    @Published private(set) var status = "Not connected"
    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?
    private var providerID: String { Bundle.main.bundleIdentifier! + ".LocalTunnel" }

    func connect() async throws {
        status = "Connecting…"
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let manager = managers.first {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == providerID
        } ?? NETunnelProviderManager()
        self.manager = manager
        let configuration = NETunnelProviderProtocol()
        configuration.providerBundleIdentifier = providerID
        configuration.serverAddress = "Local developer connection"
        configuration.disconnectOnSleep = false
        manager.protocolConfiguration = configuration
        manager.localizedDescription = "iPhomarchy Local Tunnel"
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: manager.connection, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateStatus() }
        }
        if manager.connection.status != .connected {
            try manager.connection.startVPNTunnel()
        }
        let deadline = Date().addingTimeInterval(25)
        while manager.connection.status != .connected {
            try Task.checkCancellation()
            guard Date() < deadline else {
                status = "Connection failed"
                throw OmarchyAccelerationError.message("The local tunnel did not connect. Open acceleration setup and allow the iPhomarchy VPN configuration.")
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        updateStatus()
    }

    private func updateStatus() {
        switch manager?.connection.status {
        case .connected: status = "Connected"
        case .connecting, .reasserting: status = "Connecting…"
        case .disconnecting: status = "Disconnecting…"
        default: status = "Not connected"
        }
    }
}
