# Test plan

Protocol: encode/decode roundtrip, CRC corruption, bad SOF/version/length, truncated frames, sequence/offset boundaries, Manifest HTTPS/size/hash validation.

BLE: whitelist scan, MAC dedupe, GATT identity recheck, property detection, Notify subscription, 15s prepare window, ACK loss/delay/duplicate, duplicate/out-of-order/corrupt chunks, disconnect/cancel/reconnect.

Wi-Fi: Wi-Fi unavailable, DNS/TLS/certificate/HTTP errors, interrupted download, size/hash mismatch, insufficient partition.

Power fault injection at prepare, partition init/erase, write, verify, commit and first boot. SUCCESS only after device verification, commit, reboot, reconnect and target-version readback.
