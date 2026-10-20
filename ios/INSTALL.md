# Installing the standalone development app

This is a local Omarchy emulator app based on UTM 5.0.8. You do not need a
separate UTM installation. Desktop setup, graphics and performance still need
physical iPhone testing. A successful app build does not establish a working
Omarchy desktop.

## Get a build

Open this repository's **Actions → iPhone development app** and select a
successful run on `codex/standalone-iphone`. Download
`iPhomarchy-development-app`. It contains an unsigned IPA, an Xcode archive
and these instructions. The app downloads its matching, verified image from
the development image release on first launch.

## Paid Apple Developer account

The JIT edition needs an **Apple Development** certificate with its private
key, and development provisioning profiles that include your iPhone's UDID.
An Apple Distribution certificate or App Store Connect API key alone is not
sufficient. Enable Developer Mode on the phone when prompted.

Register these explicit identifiers in your developer account:

- App: `dev.tcballard.iphomarchy.UTM`
- Helper: `dev.tcballard.iphomarchy.UTM.iOSHelper`
- App group: `group.dev.tcballard.iphomarchy.UTM`

Enable the app group on the app and helper. For the app, request Increased
Memory Limit and Extended Virtual Addressing as used by upstream UTM, and
regenerate its development profile after changing capabilities. Both profiles
must belong to your team and include the target phone. Development signing
must preserve `get-task-allow` so an authorised debugger can activate JIT.

Keep the `.p12`, its password and provisioning files out of git and chat. You
can sign the unsigned IPA on your own machine using a compatible development
signer that handles the nested iOSHelper extension. The archive is also
provided for Xcode's development export on a hosted Mac. Each bundle needs
its matching profile; signing only the top-level app is insufficient.

The build workflow deliberately does not request or store signing credentials.
Once the unsigned build passes, signing automation can use repository secrets
or remain on your own XPS. Paid membership does not itself supply the
certificate, profiles or JIT activation.

## First launch

1. Open iPhomarchy and tap **Download Omarchy** on Wi-Fi. Keep the app open.
   Setup checks storage, downloads and verifies the disk, and prepares the VM.
   Cancellation or a failed check removes the incomplete installation.
2. Set up [StikDebug](https://github.com/StikDebug/StikDebug) with the phone's
   pairing file and LocalDevVPN. Use the current UTM-compatible iOS 26 JIT
   script for **iPhomarchy**. See the
   [current JIT guide](https://docs.sidestore.io/docs/advanced/jit).
3. Return to the app, turn the phone sideways, and tap **Start Omarchy**.
4. Complete Linux account setup. Use UTM's built-in touch/keyboard toolbar or
   a Bluetooth keyboard and mouse. Shut Linux down before closing the app.

Signing does not remove the iOS JIT restriction. TestFlight distribution does
not provide the development debugging entitlement used by this edition.
The initial target is a development-signed app on an iPhone 16 Pro running
iOS 26.6.2; actual on-device acceptance is outstanding.

## Building without owning a Mac

The GitHub workflow uses a hosted macOS runner. It pins UTM source and the
matching prebuilt iOS dependency artifact in `ios/upstream.json`. If that
upstream artifact expires, replace the pin with a reviewed matching source
and dependency build; do not silently combine unrelated versions.

The overlay replaces only the iOS library screen, preserves UTM's VM session,
display, input and emulator code, and changes the display name, URL scheme and
bundle prefix. Internal UTM identifiers and source attribution are retained.
The first build retains upstream UTM artwork; a distinct app icon is pending.

The standalone app uses the downloaded disk directly, avoiding a separate ZIP
extraction and import copy. Setup requires the disk size plus one download
part and 2 GiB of headroom. The QCOW2 disk can grow towards its 20 GiB virtual
capacity, so monitor free storage after setup.

## Open-source notices

Launcher additions are MIT licensed. UTM is Apache-2.0; QEMU and its bundled
libraries have their own licenses, including GPL components. The upstream
source remains available at
https://github.com/utmapp/UTM/tree/535d6592a8bdc22b48de53703a371b80bf60d587.
This repository publishes the exact overlay and source pins; retain bundled
license notices and provide corresponding dependency source when distributing
the binary. This is an independent project, not an official Omarchy release.
