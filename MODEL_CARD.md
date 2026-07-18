# Model card

## Embedding model

- Name: MobileFaceNet-derived face embedding model
- Input: aligned 112×112 RGB face
- Output: 192-dimensional L2-normalized embedding
- SHA-256: `be4bc7cfc53f7bc336d0f28b1ab92535f618c913a422b683210750f6b5354854`
- Runtime source: `face_detection_tflite` 6.6.3
- Runtime model version: 1.1.1
- License declared by upstream distribution: Apache-2.0
- Architecture paper: MobileFaceNets, arXiv:1804.07573

## Redistribution audit status

**Publication gate: incomplete.** The upstream repository and package declare
the included models Apache-2.0, and the exact binary hash is recorded above.
However, its commit that introduced `mobilefacenet.tflite` does not identify the
training checkpoint, weight owner, training data, or conversion process. The
repository licence alone is not conclusive evidence that the contributor had
the right to relicense independently obtained model weights.

Before publishing this package, obtain written provenance/licensing confirmation
from the upstream maintainer or replace the embedding model with weights whose
origin and redistribution rights are documented end to end. Recalculate the
hash, assign a new model ID, update notices, recalibrate thresholds, and rerun
the complete cross-platform test matrix after any replacement.

This repository does not copy the binary. It consumes the model from the
declared `face_detection_tflite` dependency. The hash above is pinned in every
`FaceTemplate`; changing the model, detector, alignment, normalization, or
postprocessing requires a new pipeline/model identifier and re-enrollment.

Package startup also verifies the exact SHA-256 values of the front-face
detector, landmark, iris, and blendshape assets. The pipeline identifier binds
the combined five-asset manifest so dependency asset changes fail closed.

## Pipeline

Encoded images are decoded in Dart, EXIF orientation is baked into pixels,
explicitly mirrored input is flipped to a canonical unmirrored form, and the
canonical image is encoded as lossless PNG to avoid JPEG quantization drift.
Detection supplies eye landmarks;
the runtime applies affine eye alignment before embedding inference. The
package stores all three enrollment embeddings and their normalized centroid.

The current upstream alignment implementation uses the eyes, not a package-
owned eyes-and-nose transform. This is a documented beta limitation and must be
included in cross-platform validation or replaced before a production claim.

## Intended use and limitations

Intended for cooperative 1:1 verification in mobile applications. It is not
validated for surveillance, law enforcement, emotion inference, demographic
classification, or 1:N identification. Performance varies by camera, lighting,
occlusion, pose, age, and population. Integrators must conduct representative
accuracy and bias testing.
