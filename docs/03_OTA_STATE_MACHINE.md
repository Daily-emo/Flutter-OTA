# OTA state machine

Device happy path: IDLE -> PREPARING -> READY -> RECEIVING -> VERIFYING -> VERIFIED -> COMMITTING -> REBOOT_PENDING -> SELF_TEST -> SUCCESS.

Failure paths: REJECTED, FAILED, CANCELLED, TIMEOUT, DISCONNECTED, ROLLBACK.

App states: disconnected, scanning, connecting, discoveringServices, subscribingEvents, queryingCapabilities, preparing, ready, beginning, transferring, verifying, committing, rebootWaiting, reconnecting, versionChecking, success, failed, cancelling, cancelled.

Rules: subscribe before PREPARE; subscription success is not prepare success; device ACK/committed offset is authoritative; verify before commit; reconnect and read target version before SUCCESS; page disposal is not device abort; only one active session per device.
