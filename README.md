# Locompass
Point an arrow at nearby friends using UWB (Nearby Interaction).
Pairing is fully local via MultipeerConnectivity — no server, no accounts.

    cd app && xcodegen generate && open Locompass.xcodeproj

Requires two UWB iPhones (12+). For the precise UWB arrow both phones must
have the app open in the foreground. UWB does not work in the Simulator.

**Findable mode:** toggle "Findable while locked" and you can pocket your
locked phone — the app keeps broadcasting over BLE and serving your GPS
position in the background, so a friend can walk to you with a GPS arrow and
a Bluetooth signal-strength meter. Works fully offline (no cell service
needed). The app must stay running (don't force-quit it).

## Install (ad-hoc, registered devices only)

Open https://dseif0x.github.io/locompass/ in Safari on your iPhone and tap
**Install Locompass**. Your device's UDID must be in the ad-hoc provisioning
profile (`app/Signing/Locompass_AdHoc.mobileprovision`).

CI builds an unsigned IPA on every push to `main`, and — when the
`BUILD_CERT_P12_BASE64` secret is set — an ad-hoc signed IPA published to the
install page above.
