// Copyright 2026 Tom Ballard. MIT License.
import NetworkExtension

final class OmarchyPacketTunnelProvider: NEPacketTunnelProvider {
    private let queue = DispatchQueue(label: "dev.tcballard.iphomarchy.loopback")
    private var running = false

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: OmarchyLoopbackPacket.peer)
        let ipv4 = NEIPv4Settings(addresses: [OmarchyLoopbackPacket.address], subnetMasks: ["255.255.255.255"])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: OmarchyLoopbackPacket.peer, subnetMask: "255.255.255.255")]
        ipv4.excludedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        settings.mtu = 1500
        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else { return }
            self.queue.async {
                if error == nil {
                    self.running = true
                    self.readNext()
                }
                completionHandler(error)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        queue.async {
            self.running = false
            completionHandler()
        }
    }

    private func readNext() {
        guard running else { return }
        packetFlow.readPackets { [weak self] packets, families in
            guard let self else { return }
            self.queue.async {
                guard self.running else { return }
                var reflected: [Data] = []
                for (packet, family) in zip(packets, families) where family.int32Value == AF_INET {
                    if let response = OmarchyLoopbackPacket.reflected(packet) { reflected.append(response) }
                }
                if !reflected.isEmpty {
                    self.packetFlow.writePackets(reflected, withProtocols: Array(repeating: NSNumber(value: AF_INET), count: reflected.count))
                }
                self.readNext()
            }
        }
    }
}
