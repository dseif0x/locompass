# Compass Friends (local-only)
Point an arrow at nearby friends using UWB (Nearby Interaction).
Pairing is fully local via MultipeerConnectivity — no server, no accounts.

    cd app && xcodegen generate && open CompassFriends.xcodeproj

Requires two UWB iPhones (12+). Both must have the app open and be within
Bluetooth/Wi-Fi range. UWB does not work in the Simulator.
