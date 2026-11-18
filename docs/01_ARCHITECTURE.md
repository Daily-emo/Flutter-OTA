# Architecture

Flutter UI -> Application orchestration -> Pure Dart Protocol -> Transport adapters -> ESP32 Device OTA Manager.

BLE adapter handles scan/connect/GATT discovery/Notify/write. Wi-Fi OTA control asks the ESP32 to download its own BIN via HTTPS and polls device state; it is not phone-to-device BLE data transfer.

Both transports must call one device-side OTA manager and share session ownership, partition writer, SHA-256 verification, commit and rollback.

Suggested GATT roles:
| Characteristic | Property | Direction | Purpose |
|---|---|---|---|
| OTA Control | Write | App -> Device | query/prepare/begin/verify/commit/abort |
| OTA Data | Write or Write Without Response | App -> Device | firmware chunks |
| OTA Event | Notify/Indicate | Device -> App | ACK/state/error |

UUIDs must be confirmed from ESP32 GATT registration source. Historical beb54852/53/54 are only clues.
