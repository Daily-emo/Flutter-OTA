# MineLamp Flutter OTA

Independent Flutter/Dart OTA debugger for MineLamp ESP32-C3FH4 devices.

**Stage:** foundation and protocol proposal. Not yet verified against the current ESP32 firmware.

## Goals
- Keep this Flutter app independent from the existing UniApp.
- BLE GATT transfer with device ACK, bounded retries and diagnostics.
- Wi-Fi OTA means the ESP32 downloads BIN itself over HTTPS.
- Both transports share one device-side OTA manager, SHA-256 verification and OTA partition commit.
- No standalone .sig file; HTTPS certificate validation remains mandatory.
- Report success only after reboot, reconnect and target-version verification.

## Setup
Requires Flutter stable and Dart 3.10+:
```bash
flutter create --platforms=android,ios .
flutter pub get
dart format .
flutter analyze
flutter test
flutter run
```

See docs/ for architecture, protocol proposal, state machine, security, test plan and open firmware questions. GATT UUIDs and legacy A5 frame details are deliberately not guessed.