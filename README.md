# Omarchy iPhone Launcher

An experimental ARM64 Omarchy desktop for iPhone, using UTM's emulator.
Build it on GitHub or prepare the VM from Linux; no Mac of your own is required.

**Status:** Linux boots to a login console under ARM emulation. The Omarchy
account setup, Hyprland/Quattro desktop, UTM import and physical iPhone
compatibility are still unverified. The standalone iOS app compiles and its
installer tests pass. This is a development prototype.

The project packages [Try Omarchy](https://github.com/omacom/try-omarchy)'s
ARM64 image into a `.utm` bundle. A standalone **iPhomarchy** development app
is available as an [unsigned iOS 26+ build](https://github.com/tcballard/omarchy-iPhone-launcher/actions/runs/39366981837/artifacts/12239449578): it includes UTM's emulator,
downloads and verifies its own Omarchy disk, and provides a Start Omarchy
button. It runs locally with iOS still underneath. Read the
[standalone app installation notes](ios/INSTALL.md) for signing, JIT setup
and build status. No signed app or TestFlight release is available yet.
Paid Apple Developer accounts can use the separate
[development signing workflow](docs/signing.md) to prepare an IPA for a registered phone.

## Build on Omarchy / Arch Linux

Install the build dependencies once, then build:

```sh
sudo pacman -S --needed git nodejs curl zstd qemu-img zip
git clone https://github.com/tcballard/Omarchy-iPhone-launcher.git
cd Omarchy-iPhone-launcher
node scripts/build.mjs
```

Output: `dist/iPhomarchy.utm.zip` and its SHA-256 checksum. The build downloads
about 3 GB and produces a roughly 3.9 GB ZIP. Allow at least 25 GB free for a
fresh build; replacing an existing cached raw disk can temporarily need
another 10 GB.

The builder needs Node.js 20+, curl, zstd, qemu-img and zip. It also runs on
other Linux distributions or macOS with those tools installed. It does not
need root, a mounted disk image, Python, Docker or an Apple account.

## Test on the phone

1. Install standard [UTM for iOS](https://docs.getutm.app/installation/ios/)
   using a supported development-signing method, and enable JIT.
2. Transfer `dist/iPhomarchy.utm.zip` to the iPhone, extract it and import the
   complete `.utm` bundle in UTM. Keep its `Data` folder intact.
3. Start in landscape, complete Omarchy's account setup and test the desktop.

Read [QUICKSTART.txt](QUICKSTART.txt) for storage, input and troubleshooting
notes. The initial profile uses 2 CPU cores, 2048 MiB RAM, a 128 MiB JIT cache,
a 1280 × 720 virtual display and VirGL graphics. These are starting settings,
not verified iPhone requirements. UTM SE's slower interpreter is not the
performance target. No iPhone hypervisor acceleration is assumed.

For working entirely from an XPS or other Linux PC, including the role of
[omarchy-apple-dev v0.4.0](https://github.com/joshuaswarren/omarchy-apple-dev/releases/tag/v0.4.0),
see [Linux-to-iPhone workflow](docs/linux-iphone.md).

## Image integrity and build options

The builder pins the upstream release in [source-lock.json](source-lock.json),
checks every downloaded part's length and SHA-256, verifies the decompressed
factory image, and converts it into a standalone compressed QCOW2 disk.
`qemu-img check` validates that disk before the four-file UTM import is zipped.

Downloads can resume. Existing finished outputs are never overwritten, and
cached raw disks are rehashed before reuse. The builder never boots the
factory image, creates an owner account or embeds a shared password.

```sh
node scripts/build.mjs --cache /path/to/cache --out /path/to/new-output
node scripts/build.mjs --memory 2048 --cores 2 --graphics virgl
```

`--graphics software` creates a non-GL diagnostic profile for boot-console
investigation; it does not establish a usable Wayland desktop. The standard
profile uses UTM's combined `virtio-ramfb-gl` firmware/graphics device.
Language and UTC timezone defaults reach the guest over SMBIOS. Account
credentials are entered only in Omarchy's setup form. The Mac-specific
`omarchy.qemu_virgl=1` cursor/display setting is omitted.

## Validation

```sh
npm test
```

CI checks the JavaScript, profile tests, assembly script and builder help.
It does not download the multi-gigabyte image or test an iPhone.

[Validation notes](docs/validation.md) record the actual boot evidence,
limitations and outstanding phone acceptance checks. Each built bundle
includes `provenance.json` with its source release, hashes and profile.
QCOW2 integrity and local Linux boot do not establish iOS compatibility or
performance.

## Next milestones

1. Import and boot the VM in UTM on a named physical iPhone with JIT.
2. Complete account setup and launch Hyprland/Quattro; measure startup,
   memory, responsiveness and temperature.
3. Verify touch input, keyboard shortcuts, networking, persistence and restart.
4. Remove misleading Mac-only integrations in a separate guest package.
5. Build a dedicated iOS launcher after the VM proves usable.

## Original split test package

The first private handoff was split into nine files after its single-file
upload failed. If you already have those files, keep them together with
`scripts/Assemble-iPhomarchy.command`, then run on Linux:

```sh
bash Assemble-iPhomarchy.command
```

The assembler is pinned to that original build's checksum. It was tested on
Linux and reproduced the ZIP byte for byte. New builds from this repository
produce a single ZIP directly and do not require that assembly step. No VM
binary or public release is published by this source bootstrap.

## Sources and attribution

- [Try Omarchy](https://github.com/omacom/try-omarchy), pinned to v1.1.0 for
  the image. Its MIT license covers its project code, not every package in
  the Linux disk.
- [UTM](https://github.com/utmapp/UTM), whose v4 configuration schema and
  argument generation were inspected. UTM supplies its own QEMU and UEFI
  runtime on the phone; its code and binaries are not included here.
- [UTM display settings](https://docs.getutm.app/settings-qemu/devices/display/)
  and [iOS graphics/touch settings](https://docs.getutm.app/preferences/ios/).
- [omarchy-apple-dev](https://github.com/joshuaswarren/omarchy-apple-dev),
  evaluated as the Linux toolchain for a future native front end and device
  diagnostics. It is not yet an integrated dependency.

The source lock distinguishes the source commit inspected from the release
used for the binary image. Linux components retain their own licenses and
upstream source availability. This is an unofficial project; Omarchy and UTM
trademarks remain with their owners.
