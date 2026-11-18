# Project scope

- Target device: MineLamp ESP32-C3FH4; firmware baseline V4.1 (verify actual source).
- Client: Flutter/Dart, Android-first standalone OTA debugger.
- Firmware image: BIN. Integrity: SHA-256.
- Manifest fields: device, version, url, size, sha256, changelog.
- No standalone .sig or app-layer RSA/ECDSA/Ed25519 flow. HTTPS certificate validation remains mandatory.
- Failed or incomplete images must never be selected as boot partition.
- Do not invent GATT UUIDs or treat Notify subscription / local BLE write callback as OTA success.
- Do not modify eFuse or Secure Boot configuration in this phase.

Stages: foundation; BLE diagnostics; protocol alignment; BLE transfer; Wi-Fi HTTPS device download; unified device OTA manager, rollback and hardware tests.
