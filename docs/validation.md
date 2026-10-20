# Validation — 20 October 2026 UTC

This is a development prototype. No physical iPhone or iOS Simulator is
attached to this environment. The standalone app was compiled and packaged
on a hosted Mac. It has not been development-signed or tested on a phone.

## Source and disk integrity

- Upstream image: Try Omarchy v1.1.0, published 19 October 2026.
- All three release parts downloaded and verified against their published
  SHA-256 digests and byte lengths.
- Decompressed raw image: 21,474,836,480 bytes.
- Raw SHA-256:
  `1ce5208990dae1f30b0c8757db57b57d404effa967f995b8ea99fb1bfe83aa55`.
- `qemu-img convert -f raw -O qcow2 -c -o compat=1.1,compression_type=zlib`
  produced the standalone disk. `qemu-img check` found no errors.
- No owner account was provisioned in the delivered image. Boot tests used a
  separate writable QCOW2 overlay. The distributed factory disk was not booted.

## UTM profile

The plist uses the version 4 schema from UTM commit
`535d6592a8bdc22b48de53703a371b80bf60d587`. The actual Swift decoders,
QEMU constants, drive packaging and argument generation were inspected.
The XML was independently parsed with Apple's plist format parser in
Python's standard library; Python is not a build dependency of iPhomarchy.

The profile selects ARM64, cortex-a72, 2 CPUs, 2048 MiB RAM, 128 MiB JIT
cache, UEFI, GICv3 and `virtio-ramfb-gl`. Hypervisor is disabled. Two globals
request a 1280 x 720 GPU mode; this is a virtual display size, not an iPhone
screen-size claim. Firmware may initially choose another resolution.

Language/timezone defaults are passed using systemd's binary credential
format over SMBIOS. The initial test without this exposed a failed
`try-omarchy-locale.service`, whose implementation requires that host settings
file. The final profile supplies `en_US.UTF-8` and UTC. The Mac cursor/display
flag `omarchy.qemu_virgl=1` is deliberately absent.

No incoming network forwards, shared directories, clipboard, host USB,
audio, camera or biometric authentication have been enabled.

## Local boot smoke test

Host: Linux x86_64, QEMU 8.2.2 with TCG; ARM64 guest, cortex-a72, 2 CPUs,
2048 MiB RAM, GICv3, AAVMF UEFI, virtio block disk, USB keyboard/tablet,
virtio RNG and user-mode NAT. Kernel output was captured over a virtio console.

This host does not have UTM's combined graphics device or its iOS renderer.
The local test used the non-GL virtio GPU; a follow-up adds a separate RAMFB
to approximate the combined firmware/graphics handover. This does not test
VirGL, ANGLE, Metal, SPICE input or UTM import.

Observed in the first 240-second test:

- UEFI loaded the fallback boot entry from the disk.
- The installed Linux kernel booted, mounted its btrfs root and started systemd.
- Linux reported `Omarchy 7.2.8-14-omarchy` and presented an hvc0 login prompt.
- A real graphical boot console became active and displayed service progress.
- Deferred first-boot hardware provisioning had not completed in the observed
  window. The owner setup form and desktop were not verified.
- The upstream initramfs emitted a non-LUKS mapping warning before continuing
  into Linux user space. This has not been changed in the factory image.

A follow-up boot with the SMBIOS defaults reached Linux user space again
and reported `Finished Initialize the guest language from the Mac once`,
confirming the language bootstrap fix. The optional Mac clock-recovery unit
reported failure in this run; its cause was not diagnosed. The local RAMFB
test also lacked `vgabios-ramfb.bin`, so it does not prove the UTM firmware
framebuffer path. These are recorded limitations, not passing checks.

No timing from this x86-to-ARM test should be treated as an iPhone benchmark.

## Checks

- `node --test`: resource validation, per-VM identity isolation, XML escaping
  and the locale bootstrap credential.
- Node syntax checks for the builder and profile generator.
- Independent plist XML parse and profile invariant checks.
- Full QCOW2 structure check; no backing-file dependency.
- Final ZIP CRC check: no errors; exact four-file payload checked.
- SHA-256 of the final ZIP recorded in the adjacent checksum file.

## Acceptance still required on a phone

1. Install the signed standalone app, complete its image download and confirm JIT.
2. Reach and complete Omarchy's owner setup, then boot Hyprland/Quattro.
3. Confirm visible cursor, touch input, modifier shortcuts and terminal launch.
4. Verify outgoing networking, disk persistence and clean shutdown/restart.
5. Record startup time, memory pressure, temperature and battery use.

No item in this phone acceptance list has passed yet. A successful Linux
boot in local emulation is narrower evidence than a usable iPhone desktop.

## Standalone iOS app build

- UTM 5.0.8 source and matching prebuilt iOS dependencies are pinned.
- Hosted Xcode 27.0 builds an ARM64 archive with an iOS 26.0 minimum target.
  Apple's Metal toolchain is explicitly installed for CocoaSpice shaders.
- [Build 39366981837](https://github.com/tcballard/omarchy-iPhone-launcher/actions/runs/39366981837)
  passed all three jobs: image publication, native installer tests and the
  full app archive/package. Its artifact contains the unsigned IPA and archive.
- All five Node tests pass, including byte-exact reconstruction across image
  part boundaries, part hashes and refusal to overwrite existing output.
- Native Swift installer tests passed on macOS 26.6.2: successful install,
  overwrite protection, part and whole-disk integrity failures, cleanup of
  failed installations, fresh identities and download URL validation.
- QCOW2 image SHA-256:
  `c6d6c53b920af1f88c46890ea17923b1ced81a6c9f6b31517495316a31862745`.
  A clean CI rebuild matched the disk and all four part hashes. GitHub's
  published asset digests independently matched `ios/image-manifest.json`.
- The separate signing workflow has only received shell syntax validation.
  A real certificate/profile export, first launch, installer network flow,
  JIT activation and desktop operation on a phone remain untested.

## Original manual VM handoff

The manual assembly kit uses nine 450 MiB-or-smaller parts and checks the
exact full ZIP SHA-256. Its assembler requires a Mac or Linux computer before
transfer to the phone. The standalone app downloads four verified disk parts
directly from this repository's image release and does not require manual
assembly or a separate UTM installation.
