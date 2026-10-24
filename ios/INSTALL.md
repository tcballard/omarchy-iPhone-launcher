# iPhomarchy integrated development app

One development-signed app contains UTM/QEMU, the Omarchy installer, an
ExtensionKit JIT helper using StikJIT 1.9.0, and a local packet tunnel.
Separate StikDebug and LocalDevVPN installations are not needed by this edition.
An installer such as iLoader still runs on the computer for installation and
updates. App signing and Apple's system approval prompts remain necessary.

The target phone is an iPhone 16 Pro running iOS 27.0.1. On-device pairing
requires iOS 27; iOS 26 can import a remote pairing file from a computer.
This integrated edition requires physical device acceptance testing. Earlier
USB testing established JIT memory preparation and a Linux serial login;
the graphical desktop's inactive display remains unresolved. A successful
build does not establish a working desktop.

## Install and update

Download `iPhomarchy-development-app` from a successful **iPhone development
app** workflow run on `codex/integrated-iphone`. Its IPA is unsigned. Sign
locally using an Apple Development certificate and profiles for the target
phone, then install as an upgrade of the existing bundle. Keep the same
bundle identifier and app group to retain the downloaded disk and user data.
Do not uninstall the old app first.

All four executable bundles need matching development profiles:

| Bundle | Capabilities |
| --- | --- |
| `dev.tcballard.iphomarchy.UTM` | Existing app group, Extended Virtual Addressing, Increased Memory Limit, Network Extensions (packet tunnel), development debugging |
| `dev.tcballard.iphomarchy.UTM.iOSHelper` | Existing app group; original QEMU tools helper |
| `dev.tcballard.iphomarchy.UTM.JITHelper` | Development signing; bundled JIT helper |
| `dev.tcballard.iphomarchy.UTM.LocalTunnel` | Network Extensions (packet tunnel) |

The existing group is `group.dev.tcballard.iphomarchy.UTM`. Sign embedded
frameworks without application entitlements, each extension with its own
profile, and the main app last. Never store private keys or pairing files in
git or GitHub Actions. TestFlight signing does not supply the development
debugging entitlement used here.

## First run

1. Enable **Settings → Privacy & Security → Developer Mode**. Follow iOS's
   restart/confirmation prompts if it was disabled.
2. Open iPhomarchy → **Set up acceleration → Pair on this iPhone**. Allow
   Local Network access. In Developer Mode settings choose **Pair with
   iPhomarchy** and enter the code shown in the app or ongoing activity.
   Alternatively, import this phone's remote pairing plist created with
   iLoader/idevice. A USB-only pairing plist is insufficient.
3. Tap **Allow local tunnel and check setup** and approve the VPN configuration.
   Developer support downloads and mounts automatically. Pairing credentials
   stay in the protected app container and are excluded from backups.
4. Return home. Existing installations retain their downloaded desktop.
   New installations tap **Download Omarchy** for the verified ~4 GB disk.
5. Tap **Start Omarchy**. The app checks pairing, connects its local tunnel,
   prepares developer support, attaches its bundled helper, and starts QEMU
   only after the debugger is attached. It reports acceleration active only
   after StikJIT finishes preparing QEMU's JIT pages.

Keep the app open during setup. Shut Linux down before closing the app.
The pinned emulator starts once per app process; quit and reopen the app
before another VM start. Pairing can be repeated and developer support can
be cleared from the setup screen after an iOS update. These actions retain
the Linux disk.

## Build and verification

The workflow pins Xcode 27, UTM source/dependency artifacts in
`ios/upstream.json`, the StikJIT download/hash in
`ios/integrated-dependencies.json`, and every Rust crate in
`ios/Pairing/Cargo.lock`. It builds the iOS ARM64 pairing static library,
augments a clean UTM project with `integrate-project.rb`, and archives the
whole app. Signing remains local.

Host tests cover installer integrity and overwrite protection, packet
checksums and local-only filtering, launch gating/error/timeout/cancellation,
diagnostic-path relocation without disk changes, and pairing credential
permissions/cancellation. The Apple build checks iOS SDK integration and
extension embedding. Phone acceptance must separately check pairing in
Settings, VPN approval, first developer-support download, the QEMU allocation
breakpoint, input, and visible desktop output.

## Sources and notices

Launcher additions are MIT; UTM is Apache-2.0 and bundled QEMU/graphics
dependencies retain their licenses. StikJIT is included unmodified under
MPL-2.0. The new pairing wrapper uses MIT-licensed idevice APIs. Notices,
source links and locked Rust dependency licenses ship in the app.

LinPad's separation of acceleration status from desktop readiness informed
the startup review. LinPad uses iSH syscall translation and a native window
bridge rather than QEMU/Arch/Hyprland; no LinPad or Husk code was copied into
this integration. The full Omarchy VM remains the intended desktop.
