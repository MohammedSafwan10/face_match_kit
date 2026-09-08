## Unreleased

- Added `CaptureFlowPolicy.simpleVerification`: single straight look for
  verification, no turns.
- Aligned live pose windows with the still-enrollment gate (front ±12°,
  sides 10–42°) and widened the frame-gap tolerance for on-device inference
  latency; views now stamp arrival time instead of post-inference time.
- Added `EnrollmentResult.registrationImageBytes` (front-pose JPEG copy for
  host review-photo upload).

## 0.1.0

- Initial beta release.
- Added on-device face detection and package-owned result types.
- Replaced the unidentified MobileFaceNet pipeline with bundled, hash-pinned
  OpenCV YuNet detection and SFace INT8 128-dimensional recognition.
- Added only the required Apache-licensed MediaPipe landmark and blendshape
  models for live pose and blink guidance.
- Added versioned, JSON-serializable three-pose templates.
- Added 1:1 verification with typed compatibility and quality failures.
- Added randomized blink/head-turn basic liveness state machine.
- Added ready-made enrollment and verification camera widgets.
- Added Android/iOS example application and migration/security documentation.
- Added schema-v2 templates with secure random template IDs, strict field and
  compatibility parsing, three 128-value samples, and a verified centroid.
- Added bounded canonical preprocessing, deterministic 1600-pixel resize,
  RGB-to-BGR conversion, SFace align-crop, and four-asset integrity checks.
- Added runtime configuration and strict template validation.
- Added enrollment same-person consistency checks and per-call thresholds.
- Hardened liveness transitions, camera lifecycle handling, rotation, capture
  recovery, and immediate post-challenge capture.
- Removed the separate runtime permission dependency; camera initialization now
  owns permission requests.
- Fixed Android CameraX live detection by using its supported multi-plane
  YUV420 stream instead of an undecodable one-plane NV21 stream.
- Corrected selfie-facing left/right pose and liveness directions.
- Added responsive enrollment/verification widgets, expanded text theming,
  host error callbacks, and clearer capture guidance.
- Added stale-frame and stale-operation guards for lifecycle, template, kit,
  and configuration changes.
- Bounded serialized template dimensions and sanitized public processing
  failures so native exception details are not exposed.
- Removed `face_detection_tflite`, eleven unused transitive model assets, and
  all legacy MobileFaceNet identifiers and pipeline code.
- Added complete SFace, YuNet, and MediaPipe provenance/licence notices.
