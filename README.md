# face_match_kit

[![CI](https://github.com/MohammedSafwan10/face_match_kit/actions/workflows/ci.yml/badge.svg)](https://github.com/MohammedSafwan10/face_match_kit/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

On-device face detection, guided three-pose enrollment, basic liveness, and
1:1 face verification for Flutter on Android and iOS. No Firebase, backend, or
internet connection is required.

> **Beta:** `0.1.0` is for evaluation. The randomized blink/head-turn flow is a
> convenience barrier, not presentation-attack detection and not spoof-proof.
> Accuracy calibration and the physical Android/iOS test matrix are release
> gates documented in [PUBLISHING.md](PUBLISHING.md).

## What is bundled

The package brings its own pinned, integrity-checked on-device stack:

- OpenCV YuNet 2023mar for face detection and five landmarks
- OpenCV SFace 2021dec INT8 for 128-dimensional embeddings
- the required MediaPipe face-landmark and blendshape models for guidance
- camera, image decoding, LiteRT, OpenCV, and hashing dependencies

Applications add only `face_match_kit`; pub resolves its transitive
dependencies and Flutter bundles the required native libraries and four model
assets into the app. The first OpenCV Android build can take several minutes.

## Install

```yaml
dependencies:
  face_match_kit: ^0.1.0

# Required by opencv_dart so its native build contains YuNet and SFace.
hooks:
  user_defines:
    dartcv4:
      include_modules:
        - imgproc
        - dnn
        - objdetect
```

The hook block is currently required in the consuming application's root
`pubspec.yaml`; Dart native-asset settings cannot be forced by a transitive
package. It does not add another dependency.

Android requires API 26 or later and camera permission:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera.front" android:required="true" />
```

iOS 15.5 or later requires:

```xml
<key>NSCameraUsageDescription</key>
<string>We use the camera for on-device face verification.</string>
```

## Ready-made UI

```dart
FaceEnrollmentView(
  onCompleted: (result) async {
    if (result.isSuccess) await saveTemplate(result.template!.toJson());
  },
);

FaceVerificationView(
  template: FaceTemplate.fromJson(savedJson),
  onCompleted: (result) {
    if (result.isMatch) unlock();
  },
);
```

The widgets own permission handling, camera preview, quality guidance,
three-pose capture, basic liveness, retry, lifecycle recovery, and immediate
automatic capture after the challenge. Text, colours, thresholds, liveness,
callbacks, and the face overlay are customizable.

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
);

await kit.dispose();
```

Custom camera interfaces use the exported `FaceCameraFrame` adapter and
`detectCameraFrame`. Routine failures return typed results; corrupt model
assets or initialization failures throw.

## Canonical pipeline and templates

Encoded still images are size-checked, decoded in Dart, EXIF-oriented,
explicitly unmirrored, deterministically limited to 1600 pixels on the longest
side, converted from RGB to OpenCV BGR, detected with YuNet, aligned with
`FaceRecognizerSF.alignCrop`, embedded by SFace, and L2-normalized.

Schema-v2 `FaceTemplate` JSON contains a secure random template ID, exact
model/pipeline identity, three 128-value unit embeddings, their normalized
centroid, and creation time. Parsing rejects unknown fields, wrong lengths,
non-finite values, incompatible identities, non-unit vectors, and centroid
tampering. Every template made by the earlier 192-dimensional pipeline must be
re-enrolled; it cannot be converted safely.

## Thresholds and accuracy

The default cosine threshold `0.363` is only OpenCV's pairwise benchmark
starting point. Comparing against a three-sample centroid has a different score
distribution, and the enrollment-consistency threshold is also provisional.
Before production, calibrate representative genuine, impostor, and mixed-person
pairs. The release target is a measured FAR upper confidence bound at or below
0.1%, FRR at or below 5%, and at least 99.9% mixed-person enrollment rejection.

The JSON format is platform-portable, but equivalent Android/iOS embeddings
and all four verification directions remain to be demonstrated on physical
devices before a cross-platform accuracy claim.

## Privacy and security

Processing is local and the package makes no network calls. Camera widgets do
not deliberately retain images and make a best-effort attempt to delete camera
temporary files after reading them; managed memory is not guaranteed to be
zeroized. Templates are sensitive biometric data. The host application owns
consent, authenticated encryption, account/tenant binding, access control,
retention, deletion, revocation, audit, and breach obligations.

See [PRIVACY.md](PRIVACY.md), [SECURITY.md](SECURITY.md),
[MIGRATION.md](MIGRATION.md), and [MODEL_CARD.md](MODEL_CARD.md).

## Scope and licence

Version 0.1 supports cooperative 1:1 verification on Android and iOS. It does
not provide 1:N identification, web/desktop support, surveillance, or advanced
anti-spoofing.

Package source is Apache-2.0 and may be used commercially subject to its terms
and required notices. YuNet carries a separate MIT notice. Model licensing and
remaining training-data provenance risk are documented in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[MODEL_CARD.md](MODEL_CARD.md); commercial release requires legal acceptance
of that remaining risk or authoritative clarification.
