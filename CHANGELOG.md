## 0.1.0

- Initial beta release.
- Added on-device face detection and package-owned result types.
- Added canonical image normalization and eye-aligned MobileFaceNet embeddings.
- Added versioned, JSON-serializable three-pose templates.
- Added 1:1 verification with typed compatibility and quality failures.
- Added randomized blink/head-turn basic liveness state machine.
- Added ready-made enrollment and verification camera widgets.
- Added Android/iOS example application and migration/security documentation.
- Added lossless canonical preprocessing and strict five-asset integrity checks.
- Added runtime configuration and strict template validation.
- Added enrollment same-person consistency checks and per-call thresholds.
- Hardened liveness transitions, camera lifecycle handling, rotation, capture
  recovery, and immediate post-challenge capture.
- Removed the separate runtime permission dependency; camera initialization now
  owns permission requests.
