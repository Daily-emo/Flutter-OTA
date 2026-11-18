# Security and rollback

Decision: no standalone .sig and no app-layer RSA/ECDSA/Ed25519 signature flow. Keep HTTPS certificate validation and SHA-256.

SHA-256 verifies consistency against the expected digest; it does not authenticate publisher identity if BIN and Manifest can both be replaced. HTTPS protects transport/server identity but cannot protect a compromised trusted server.

Require TLS hostname/certificate validation, BLE pairing/encryption review, valid OTA session access, Manifest device/version/size/hash validation, and no boot partition switch on hash/image-check failure. MAC is not cryptographic authentication.

Write inactive OTA slot -> verify size -> SHA-256 -> image validation -> set boot partition -> reboot -> self-test -> mark valid only if rollback is enabled and self-test passes. Confirm actual flash capacity, partition table and rollback build config before claiming rollback support.
