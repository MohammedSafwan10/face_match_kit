# face_match_kit

[![CI](https://github.com/MohammedSafwan10/face_match_kit/actions/workflows/ci.yml/badge.svg)](https://github.com/MohammedSafwan10/face_match_kit/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

On-device face detection, guided enrollment, basic liveness challenges, and
1:1 face verification for Flutter on Android and iOS.

`face_match_kit` returns versioned biometric templates to your application. It
does not require Firebase, a backend, or a network connection, and it does not
retain captured images by default.

> **Beta:** `0.1.0` is intended for evaluation. The included blink/head-turn
> challenge is a convenience barrier, not advanced presentation-attack
> detection. Do not describe it as spoof-proof.
>
> **Publication gate:** the exact model is hash-pinned, but its original
> weight provenance is not yet documented end to end. See
> [MODEL_CARD.md](MODEL_CARD.md) before publishing this package.

## Features

- Detection with package-owned result types
- Three-pose enrollment: front, slight left, slight right
- Eye-aligned 192-dimensional MobileFaceNet embeddings
- Lossless, orientation-normalized still-image preprocessing on both platforms
- Startup integrity checks for every detector, landmark, and embedding asset
- Strict model and preprocessing version checks
- Versioned template format designed for Android/iOS portability (physical
  cross-platform equivalence validation is still pending)
- Ready-made enrollment and verification camera widgets
- Low-level image APIs for custom interfaces
- App-owned template persistence

## Install

```yaml
dependencies:
  face_match_kit: ^0.1.0
```

Android requires API 26 or later and camera permission:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera.front" android:required="true" />
```

The detector compiles native OpenCV assets on the first Android build. Install
an Android NDK (side by side) and CMake through Android Studio's SDK Manager.
The first build can take several minutes; later builds use the native-assets
cache. On Windows, if NDK discovery fails, ensure `ANDROID_HOME` uses a path
that the build hook can resolve (forward slashes avoid drive-path parsing
issues in some toolchain versions).

iOS 15.5 or later requires a camera usage description in `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>We use the camera for on-device face verification.</string>
```

Test iOS recognition on a physical device. Lock the capture flow to portrait
when supplying your own camera frames.

The ready-made widgets let the `camera` plugin request access when the camera is
opened; no separate runtime permission package is required. The platform
manifest entries above are still mandatory.

## Ready-made UI

```dart
FaceEnrollmentView(
  onCompleted: (result) async {
    if (result.isSuccess) {
      await saveJson(result.template!.toJson());
    }
  },
);

FaceVerificationView(
  template: FaceTemplate.fromJson(savedJson),
  onCompleted: (result) {
    if (result.isMatch) unlock();
  },
);
```

Both widgets support custom text, colors, thresholds, liveness enablement, and
an overlay builder.

## Low-level API

```dart
final kit = await FaceMatchKit.create();

final detection = await kit.detect(jpegBytes);

final enrollment = await kit.enroll(samples: [
  FaceSample(imageBytes: front, pose: FacePose.front),
  FaceSample(imageBytes: left, pose: FacePose.slightLeft),
  FaceSample(imageBytes: right, pose: FacePose.slightRight),
]);

final verification = await kit.verify(
  imageBytes: probe,
  template: enrollment.template!,
  threshold: 0.62, // Optional; replace with your calibrated value.
);

await kit.dispose();
```

Routine conditions such as no face, multiple faces, low quality, an
incompatible template, or a threshold mismatch are returned through typed
results. Initialization/model failures may throw.

## Privacy and storage

A `FaceTemplate` is sensitive biometric data even though it is not a photograph.
The integrating application is responsible for consent, encryption, access
control, retention, deletion, breach handling, and applicable biometric laws.
Do not place templates in logs or analytics.

The package never uploads templates or images. Camera widgets attempt to delete
temporary captures immediately after reading; deletion is best-effort because
the operating system or camera plugin may already have moved or removed the
file. Captured bytes can remain in managed memory until garbage collection and
are not guaranteed to be zeroized. See [PRIVACY.md](PRIVACY.md),
[SECURITY.md](SECURITY.md), and [MIGRATION.md](MIGRATION.md).

## Accuracy

The default similarity threshold (`0.60`) and enrollment-consistency threshold
(`0.45`) are provisional. Calibrate them using
genuine and impostor pairs from the devices, lighting, distance, and population
your application supports. Publish FAR/FRR with any security claim.

The template schema is cross-platform by construction, but production release
claims require physical-device testing in all four directions: Android→Android,
Android→iOS, iOS→Android, and iOS→iOS.

## Scope

Version 0.1 provides 1:1 verification: “Is this the enrolled user?” It does not
perform 1:N identification across a gallery. Web, desktop, and advanced
anti-spoofing are outside the supported scope.

## Example

Run `cd example && flutter run` on an Android or iOS device. The example keeps
the template only in memory and demonstrates explicit deletion.

## License and project identity

The package source is available under the [Apache License 2.0](LICENSE). You may
use, modify, and distribute it, including commercially, while preserving the
licence and required notices. Apache-2.0 also includes an explicit patent grant.

That source-code licence is not a representation that every independently
trained model checkpoint has been cleared. Commercial publication remains
blocked by the embedding-weight provenance described in
[MODEL_CARD.md](MODEL_CARD.md). See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the resolved software and
model inventory.

The licence does not grant permission to present an unofficial fork as an
official Face Match Kit release or to imply endorsement. See
[TRADEMARKS.md](TRADEMARKS.md).

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) and keep the
model-provenance and accuracy gates in [PUBLISHING.md](PUBLISHING.md) intact.
