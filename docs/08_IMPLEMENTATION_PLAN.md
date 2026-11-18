# Implementation plan

P0 foundation and protocol proposal (current). P1 Android BLE permissions, 5-second whitelist scan, MAC dedupe, GATT discovery and raw HEX logs. P2 QUERY_CAPS/PREPARE correlation and 20 consecutive prepare tests. P3 BIN, SHA-256, MTU-aware chunks, ACK/retry/flow control/cancel. P4 HTTPS Manifest and device-side Wi-Fi download status. P5 unified device OTA manager, dual slot, self-test, rollback and power-loss tests. P6 evaluate migration into MineLamp main app.

Do not mask prepare timeout by merely increasing timers. Each phase gets separate builds/tests and rollback point.
