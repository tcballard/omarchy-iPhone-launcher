// Copyright 2026 Tom Ballard. Licensed under the MIT License.
import SwiftUI

@MainActor
private final class OmarchySetup: ObservableObject {
    @Published var isInstalling = false
    @Published var progress = 0.0
    @Published var status = ""
    @Published var error: String?
    private var task: Task<Void, Never>?

    func install(data: UTMData) {
        guard task == nil else { return }
        error = nil
        progress = 0
        status = "Preparing download…"
        isInstalling = true
        UIApplication.shared.isIdleTimerDisabled = true
        task = Task {
            defer {
                isInstalling = false
                task = nil
                UIApplication.shared.isIdleTimerDisabled = false
            }
            do {
                guard let encoded = Data(base64Encoded: "__OMARCHY_MANIFEST_BASE64__") else {
                    throw OmarchyInstallError.invalidManifest
                }
                let payload = try JSONDecoder().decode(OmarchyPayload.self, from: encoded)
                try await OmarchyInstaller().install(payload, documents: UTMData.defaultStorageUrl) { fraction, label in
                    Task { @MainActor [weak self] in
                        self?.progress = fraction
                        self?.status = label
                    }
                }
                await data.listRefresh()
            } catch is CancellationError {
                status = "Download cancelled. You can start again whenever you’re ready."
            } catch let failure as URLError where failure.code == .cancelled {
                status = "Download cancelled."
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func cancel() { task?.cancel() }
}

@MainActor
struct OmarchyHomeView: View {
    @EnvironmentObject private var data: UTMData
    @StateObject private var setup = OmarchySetup()
    @State private var refreshed = false
    @State private var accelerationHelp = false
    private let accent = Color(red: 0.65, green: 0.89, blue: 0.32)

    private var machine: VMData? {
        data.virtualMachines.first { $0.pathUrl.lastPathComponent == "iPhomarchy.utm" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Image(systemName: "terminal.fill").foregroundColor(accent)
                    Text("iPhomarchy").font(.headline.monospaced())
                    Spacer()
                    Text("EXPERIMENTAL").font(.caption2.monospaced()).foregroundColor(.secondary)
                }
                .accessibilityElement(children: .combine)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your pocket\nOmarchy.").font(.system(size: 44, weight: .bold, design: .monospaced))
                        .minimumScaleFactor(0.7)
                    Text("A local Linux desktop, on your iPhone.")
                        .font(.title3).foregroundColor(.secondary)
                }

                if !refreshed {
                    ProgressView("Checking your desktop…")
                } else if let machine = machine {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Omarchy is installed", systemImage: "checkmark.circle.fill").foregroundColor(accent)
                        Text("Enable acceleration before starting. On first boot, Omarchy will help you create your account.")
                            .foregroundColor(.secondary)
                        Button {
                            data.run(vm: machine)
                        } label: {
                            Label("Start Omarchy", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(accent).foregroundColor(.black)
                        .accessibilityIdentifier("startOmarchy")
                    }
                } else if setup.isInstalling {
                    VStack(alignment: .leading, spacing: 14) {
                        ProgressView(value: setup.progress).tint(accent)
                        Text(setup.status).font(.subheadline.monospaced())
                        Text("Keep the app open while setup completes. Your screen will stay awake.")
                            .font(.footnote).foregroundColor(.secondary)
                        Button("Cancel download", role: .cancel) { setup.cancel() }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Install your desktop").font(.title2.bold())
                        Text("Download about 4 GB once. Setup checks every part and prepares a private desktop on this phone.")
                            .foregroundColor(.secondary)
                        Button { setup.install(data: data) } label: {
                            Label(setup.error == nil ? "Download Omarchy" : "Retry download", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(accent).foregroundColor(.black)
                        .accessibilityIdentifier("downloadOmarchy")
                        if let error = setup.error {
                            Text(error).font(.callout).foregroundColor(.orange).accessibilityLabel("Setup error: \(error)")
                        } else if !setup.status.isEmpty {
                            Text(setup.status).font(.callout).foregroundColor(.secondary)
                        }
                    }
                }

                Divider()
                Button { accelerationHelp = true } label: {
                    Label("Set up acceleration", systemImage: "bolt.fill")
                }.foregroundColor(accent)
                Text("Turn your phone sideways for more space. Connect a keyboard and mouse, or use the built-in touch controls. Shut down Linux before closing the app.")
                    .font(.footnote).foregroundColor(.secondary)
                Text("Powered by UTM, QEMU and Try Omarchy. An independent, experimental project. Desktop compatibility and performance still need iPhone testing.")
                    .font(.caption).foregroundColor(.secondary)
                Link("Source and open-source notices", destination: URL(string: "https://github.com/tcballard/omarchy-iPhone-launcher")!)
                    .font(.footnote).foregroundColor(accent)
            }
            .padding(28).frame(maxWidth: 600, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(Color(red: 0.07, green: 0.08, blue: 0.09))
        .preferredColorScheme(.dark)
        .task {
            await data.listRefresh()
            refreshed = true
        }
        .alert(item: $data.alertItem) { item in
            switch item {
            case .message(let message): return Alert(title: Text(message))
            case .localizedMessage(let message): return Alert(title: Text(message))
            case .downloadUrl: return Alert(title: Text("Use Download Omarchy to install this desktop."))
            }
        }
        .sheet(isPresented: $accelerationHelp) {
            OmarchyAccelerationHelp()
        }
    }
}

private struct OmarchyAccelerationHelp: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("First-time setup")) {
                    Text("Install this app with an Apple Development certificate and a provisioning profile that includes this phone.")
                    Text("Set up StikDebug with your phone’s pairing file and LocalDevVPN. Signing alone does not enable acceleration.")
                    Text("On iOS 26, use StikDebug’s UTM-compatible script for this app, then return here and start Omarchy. Repeat activation when required after restarting the app or phone.")
                    Link("Open the current setup guide", destination: URL(string: "https://docs.sidestore.io/docs/advanced/jit")!)
                }
                Section(header: Text("About this build")) {
                    Text("The emulator runs locally. No separate UTM installation is required. This build has not yet been validated on a physical iPhone.")
                    Text("If startup fails, stop and check the setup guide. iOS updates can change acceleration compatibility.")
                }
            }
            .navigationTitle("Acceleration")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.navigationViewStyle(.stack)
    }
}
