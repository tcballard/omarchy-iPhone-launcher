# Signing with a paid Apple Developer account

The standalone app can be built on GitHub's hosted Mac and signed with your
own development certificate. The signing workflow is separate from the
unsigned build. It runs only when manually requested, after its workflow file
is on the default branch. It has not yet been exercised with a real account.

First create the app, helper and app group described in
[the app installation notes](../ios/INSTALL.md), register the phone, and
create **development** profiles for both bundles. Export an **Apple
Development** certificate and its private key as a password-protected `.p12`.

Add these under **Repository Settings → Secrets and variables → Actions →
Repository secrets**:

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_P12_BASE64` | Base64 contents of the `.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | Its export password |
| `APPLE_APP_PROFILE_BASE64` | Base64 app `.mobileprovision` |
| `APPLE_HELPER_PROFILE_BASE64` | Base64 helper `.mobileprovision` |

Generate Base64 on your own machine. Paste it directly into the relevant
GitHub secret, never a chat, issue, commit or workflow log. Keep the original
files on your own machine. Paid membership allows you to create these items;
it does not replace them.

Once **iPhone development app** succeeds, note its run ID from the Actions URL.
Run **Sign iPhone development app**, entering that run ID. Download the
`iPhomarchy-signed-development-app` artifact. Signing validates the team,
bundle IDs, development debugging entitlement and existence of registered
devices; Xcode checks the certificate and profile validity during export.
Ensure both profiles include the intended iPhone before running it.

The credentials are decoded only on an ephemeral Mac runner. Its temporary
keychain, decoded credential files and installed profiles are removed when
the script exits. The resulting IPA is a development build for registered
devices. It still needs JIT activation and is not a TestFlight build.

Installing that IPA and proving the Omarchy desktop works on a physical
iPhone are separate acceptance steps. Keep the release labelled experimental
until account creation, graphics, input, shutdown and restart have been tested.
