# Linux-to-iPhone workflow

An Omarchy/XPS or another Linux PC is sufficient to build and assemble the
current VM package. A Mac is not a prerequisite.

## Build the VM

Follow the root README's Omarchy dependency install and run:

```sh
node scripts/build.mjs
```

The result is a UTM bundle ZIP, not a signed iPhone application. This step
needs no iOS SDK, Apple ID, device pairing or omarchy-apple-dev installation.
Transfer the ZIP to the phone and import it in a separately installed UTM.
A USB cable, network file transfer or another supported file-transfer method
can carry the ZIP; AirDrop is not required.

## Assemble the original split handoff

If using the original nine-part test package, extract its assembly kit next
to the part files. From the extracted kit directory:

```sh
bash Assemble-iPhomarchy.command
```

The script also finds parts in its parent folder. It verifies every part when
the manifest is present, joins all nine and checks the full ZIP's size and
SHA-256. Linux assembly was tested byte for byte against the original ZIP.
The script also runs on macOS, where its `.command` extension allows a
Terminal double-click; that extension does not make it Mac-only.

## omarchy-apple-dev v0.4.0

Source inspected:
https://github.com/joshuaswarren/omarchy-apple-dev/releases/tag/v0.4.0

The project supplies Linux tooling for Swift/SwiftUI builds, development
signing, USB installation and device diagnostics. Its documented USB path can
use a free Apple ID. Its native app build/deploy path is relevant to a future
iPhomarchy front end and to investigating device-side failures.

It has two setup modes. Full mode obtains the iOS SDK from Apple's Xcode
archive without installing macOS. Experimental no-Xcode mode supplies a
limited set of frameworks and SwiftUI types. A QEMU-based native front end
has not been built with either mode here. Full mode is the initial candidate
for that investigation; the SDK and Swift versions must match as documented
upstream.

To inspect the same pinned toolchain on an Omarchy machine:

```sh
git clone --branch v0.4.0 --depth 1 https://github.com/joshuaswarren/omarchy-apple-dev.git
cd omarchy-apple-dev
# Read GETTING-STARTED.md before installing. Full mode needs the matching
# Apple SDK download and device work needs your Apple ID and iPhone.
./install-toolchain.sh --mode full
```

This installation has not been run on the user's XPS by this project. Keep
Apple authentication, signing keys, profiles and device pairing records out
of this repository.

## Device runtime and JIT

The current phone runtime is standard UTM for iOS. UTM's documented signing
requirements include development signing and `get-task-allow`; current builds
also contain a helper extension with its own signing profile. A generic
single-app signing example is not proof that a complete UTM IPA is signed
correctly.

JIT needs its own supported activation method. Neither a successful SwiftUI
build nor development signing demonstrates JIT activation. The actual phone's
iOS version, UTM version, signing method and JIT method need to be recorded
with its boot result.

UTM itself uses QEMU, SPICE and platform build dependencies. The xtool adapter
for ordinary Xcode projects has not been demonstrated to build UTM or its
native dependencies here. Do not treat it as a drop-in UTM cross-build.

## First device acceptance record

Record these when the physical test happens:

- iPhone model and iOS version.
- UTM version, development signing route and JIT activation method.
- VM ZIP checksum and selected CPU/RAM/graphics profile.
- Last boot screen, owner setup result and Hyprland/Quattro result.
- Touch/keyboard input, outgoing networking and persistence after restart.
- Startup time, memory pressure, temperature and battery behaviour.

No physical iPhone acceptance record exists yet. The verified local result
is ARM Linux boot to a login console; the account setup and full desktop
remain outstanding.
