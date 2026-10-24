// Copyright 2026 Tom Ballard. MIT License.
import SwiftUI
import UniformTypeIdentifiers

struct OmarchyAccelerationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var acceleration: OmarchyAcceleration
    @State private var importing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Pair this iPhone once, then allow its local tunnel. iPhomarchy includes the JIT helper and activates it when you start your desktop.")
                    Text("Developer Mode must be enabled in Settings → Privacy & Security. iOS may ask you to restart the phone when enabling it.")
                        .foregroundStyle(.secondary)
                }
                OmarchyPairingSection(pairing: acceleration.pairing, importing: $importing)
                    .disabled(acceleration.isBusy)
                Section("2. Check acceleration") {
                    OmarchyTunnelStatus(tunnel: acceleration.tunnel)
                    Button("Allow local tunnel and check setup") { acceleration.checkSetup() }
                        .disabled(acceleration.isBusy || acceleration.pairing.isPairing || !acceleration.pairing.isPaired)
                        .accessibilityIdentifier("checkAccelerationSetup")
                    Text("Allow the VPN configuration when iOS asks. The tunnel connects only to this iPhone’s developer services. Developer support files download automatically on the first check.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if acceleration.isBusy { ProgressView().accessibilityLabel("Preparing acceleration") }
                    Text(acceleration.status).font(.callout).accessibilityIdentifier("accelerationStatus")
                    if let error = acceleration.error {
                        Text(error).foregroundStyle(.orange).textSelection(.enabled)
                            .accessibilityIdentifier("accelerationError")
                    }
                }
                Section("Recovery") {
                    Button("Download developer support again") { acceleration.resetDeveloperSupport() }
                        .disabled(acceleration.isBusy || acceleration.pairing.isPairing)
                    Text("Use this after an iOS update if checking developer support fails. Your desktop and files are kept.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Included components") {
                    Text("StikJIT 1.9.0 (MPL-2.0) and idevice 0.1.68 (MIT). Their licenses and pinned source links are included in the app’s Notices folder.")
                        .font(.footnote)
                    Link("StikJIT source", destination: URL(string: "https://github.com/StikDebug/StikJIT/tree/1.9.0")!)
                    Link("Pairing library source", destination: URL(string: "https://github.com/jkcoxson/idevice/tree/v0.1.68")!)
                }
            }
            .navigationTitle("Acceleration setup")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
                switch result {
                case .success(let url): acceleration.pairing.importFile(url)
                case .failure: break // The system file picker already reports provider errors.
                }
            }
        }
    }
}

private struct OmarchyPairingSection: View {
    @ObservedObject var pairing: OmarchyDevicePairing
    @Binding var importing: Bool

    var body: some View {
        Section("1. Pair this iPhone") {
            Label(pairing.isPaired ? "Pairing saved on this iPhone" : "Pairing required",
                  systemImage: pairing.isPaired ? "checkmark.circle.fill" : "iphone")
            if pairing.isPairing {
                ProgressView("Pairing with this iPhone…")
                if let code = pairing.code {
                    Text(code).font(.largeTitle.monospaced().bold()).textSelection(.enabled)
                        .accessibilityLabel("Pairing code: \(code)").accessibilityIdentifier("pairingCode")
                }
                Text(pairing.status).font(.callout)
                Text("The pairing code also appears in iOS’s ongoing activity while you are in Settings.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Cancel pairing", role: .cancel) { pairing.cancel() }
            } else {
                if #available(iOS 27, *) {
                    Button(pairing.isPaired ? "Pair this iPhone again" : "Pair on this iPhone") { pairing.start() }
                        .accessibilityIdentifier("pairThisIPhone")
                }
                Button("Import a pairing file…") { importing = true }.accessibilityIdentifier("importPairing")
                if !pairing.status.isEmpty { Text(pairing.status).font(.callout) }
            }
            if let error = pairing.error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
        }
    }
}

private struct OmarchyTunnelStatus: View {
    @ObservedObject var tunnel: OmarchyLocalTunnel
    var body: some View { LabeledContent("Local tunnel", value: tunnel.status) }
}
