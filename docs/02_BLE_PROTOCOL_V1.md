# BLE protocol V1.0 proposal

**Proposal only. Not yet byte-for-byte compatible with current firmware.**

All multibyte integers little-endian. SOF=0xA5, version=0x01. Control frame:
| Field | Bytes |
|---|---:|
| SOF | 1 |
| Version | 1 |
| Command | 1 |
| Flags | 1 |
| Request ID | 2 |
| Session ID | 4 |
| Payload Length | 2 |
| Payload | N |
| CRC16 | 2 |

CRC: CRC-16/CCITT-FALSE, poly 0x1021, init 0xFFFF, refin/refout false, xorout 0. Covers Version through Payload, excluding SOF and CRC. Fixed overhead 14 bytes.

Flags: bit0 RESPONSE, bit1 ERROR, bit2 ACK_REQUIRED, bit3 FINAL.

Data packet: Sequence:u32 + Offset:u32 + DataLength:u16 + Data + CRC16:u16. CRC covers Sequence through Data. Payload cap = min(negotiated ATT MTU - 3 - 12, device cap, platform write cap). V1 begins with one-packet ACK flow control; optimize only after measurement.

Commands: 0x01 QUERY_CAPS; 0x02 OTA_PREPARE; 0x03 OTA_BEGIN; 0x04 OTA_DATA; 0x05 OTA_QUERY_STATUS; 0x06 OTA_VERIFY; 0x07 OTA_COMMIT; 0x08 OTA_ABORT; 0x09 OTA_WIFI_START; 0x0A OTA_EVENT.

Flow: QUERY_CAPS -> PREPARE -> BEGIN -> DATA/ACK -> VERIFY -> COMMIT -> reboot -> reconnect/version check. READY requires explicit device PREPARE_RESULT. SUCCESS requires reconnect and target version.

Known prepare window is approximately 15s after power-on from historical project notes; exact start/boundary behavior must be confirmed in firmware.

Manifest example fields: device, version, url (HTTPS), size, sha256 (64 hex), changelog.

Before freezing: confirm complete GATT UUIDs, roles/properties, legacy A5 frame and CRC, OTA_PREPARE opcode, 15s window, flash/partition table, rollback config and Wi-Fi OTA trigger.
