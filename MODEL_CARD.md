# Model card

## Runtime model inventory

| Role | Model | Bytes | SHA-256 | Source and licence |
|---|---|---:|---|---|
| Recognition | OpenCV SFace 2021dec INT8 | 9,896,933 | `2b0e941e6f16cc048c20aee0c8e31f569118f65d702914540f7bfdc14048d78a` | OpenCV Zoo commit `088c3571ec70df15100a5e4c26894d95951e92e9`, Apache-2.0 |
| Detection | YuNet 2023mar | 232,589 | `8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4` | OpenCV Zoo commit `f12e12798e8314f7c074a6656816c048dcc95b7a`, MIT |
| Guidance | MediaPipe face landmarks | 2,553,590 | `c7d54204ce0448474c7f3fa9af494787c0965cbdd6f20fc72867e43046bd43d5` | Extracted from official Face Landmarker float16/1 task, Apache-2.0 |
| Guidance | MediaPipe face blendshapes | 955,312 | `4f36dded049db18d76048567439b2a7f58f1daabc00d78bfe8f3ad396a2d2082` | Extracted from the same task, Apache-2.0 |

The official MediaPipe task archive is 3,758,596 bytes with SHA-256
`64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff`.
Only the two required TFLite files are bundled.

## Recognition contract

SFace receives an OpenCV-aligned 112×112 face and produces 128 floating-point
features. The package verifies the length and finiteness and L2-normalizes the
feature before comparison or storage. Cosine similarity is used for 1:1
verification.

The canonical still pipeline is: encoded-byte and header limits; Dart decode;
EXIF orientation; explicit mirror removal; deterministic longest-side resize
to at most 1600 pixels; RGB-to-BGR conversion; YuNet detection and five
landmarks; `FaceRecognizerSF.alignCrop`; SFace inference; L2 normalization.
The pipeline identity binds these rules, the tested dependency versions, and a
deterministically ordered four-asset hash manifest.

## Basic liveness guidance

YuNet supplies the live face region. The MediaPipe landmark model uses a
rotated, expanded 256×256 face ROI; the required 146 landmarks feed the
blendshape model. Eye-open probability is `1 - eyeBlinkLeft/right`. Head pose is
estimated from landmark geometry. Multiple stable neutral/action/return frames,
face continuity, reset on face loss/multiple faces, short expiry, and immediate
capture reduce accidental challenge completion.

This implementation is not the full MediaPipe Tasks graph and parity with the
official task remains a beta validation gate. It is not presentation-attack
detection.

## Calibration status

The default cosine threshold `0.363` is OpenCV's published pairwise benchmark
starting point, not a package calibration. This package compares a probe to a
normalized three-sample centroid, which changes the score distribution. No
FAR/FRR claim is made yet.

Release calibration must use consented representative genuine and impostor
pairs across all four Android/iOS directions. Choose a threshold that maximizes
genuine acceptance while the FAR upper confidence bound is at most 0.1%; block
release if FRR exceeds 5%. Enrollment consistency must accept at least 95% of
valid three-pose sets and reject at least 99.9% of mixed-person sets.

## Intended use and limitations

Intended for cooperative, on-device 1:1 verification in Android/iOS apps. It is
not validated for surveillance, law enforcement, 1:N identification, emotion
inference, demographic classification, or high-security biometric access.
Performance can vary with camera, lighting, blur, occlusion, glasses, pose,
age, skin tone, and population.

## Commercial-risk status

The exact SFace binary is distributed by OpenCV Zoo as Apache-2.0. The public
model description does not provide a complete checkpoint/training-data chain
of title. In particular, an upstream software/model licence does not itself
resolve privacy or contractual restrictions attached to all training data.

Commercial release therefore requires either authoritative clarification for
the exact weight or a documented legal/business acceptance of the remaining
training-data provenance risk. This is a release decision, not a claim that the
model is unlawful.
