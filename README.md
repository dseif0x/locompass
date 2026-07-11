# Locompass
Point an arrow at nearby friends using UWB (Nearby Interaction).
Pairing is fully local via MultipeerConnectivity — no server, no accounts.

    cd app && xcodegen generate && open Locompass.xcodeproj

Requires two UWB iPhones (12+). Both must have the app open and be within
Bluetooth/Wi-Fi range. UWB does not work in the Simulator.

## Install (ad-hoc, registered devices only)

Open https://dseif0x.github.io/locompass/ in Safari on your iPhone and tap
**Install Locompass**. Your device's UDID must be in the ad-hoc provisioning
profile (`app/Signing/Locompass_AdHoc.mobileprovision`).

CI builds an unsigned IPA on every push to `main`, and — when the
`BUILD_CERT_P12_BASE64` secret is set — an ad-hoc signed IPA published to the
install page above.
