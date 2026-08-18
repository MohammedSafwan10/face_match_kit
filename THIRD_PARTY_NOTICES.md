# Third-party software and model notices

This inventory applies to the dependency versions resolved for the `0.1.0`
release candidate. The package's own source is Apache-2.0 licensed. Integrators
must also preserve the licence files and notices supplied by Flutter and each
resolved dependency in their distributed application.

## Runtime software

| Component | Resolved version | Declared licence | Purpose |
| --- | ---: | --- | --- |
| Flutter SDK | installed SDK | BSD-style | UI and platform runtime |
| `camera` | 0.12.0+2 | BSD-3-Clause | Android/iOS camera access |
| `crypto` | 3.0.7 | BSD-3-Clause | SHA-256 integrity checks |
| `face_detection_tflite` | 6.6.3 | Apache-2.0 | Detection, landmarks and embedding runtime |
| `flutter_litert` | 3.5.1 | Apache-2.0 | LiteRT/TFLite execution |
| `image` | 4.5.1 | MIT, with separately noticed bundled components | Image decoding and canonicalization |
| `opencv_dart` / `dartcv4` | 2.2.1+4 | Apache-2.0 | Native image processing used transitively |

The authoritative licence text for each dependency is the `LICENSE` (and any
`NOTICE`) file distributed in that dependency's pub.dev archive. This summary
does not replace those files.

## Model assets distributed transitively

`face_detection_tflite` declares twelve TFLite assets. A consuming Flutter app
can therefore redistribute assets that `face_match_kit` does not call directly.
The complete set in version 6.6.3 is:

| Asset | Bytes | SHA-256 |
| --- | ---: | --- |
| `face_detection_back.tflite` | 315332 | `e376cf6b168d5ece8a3cedb94acc4eb168a136aede125ccc3d903ef38f5beda8` |
| `face_detection_front.tflite` | 229032 | `3bc182eb9f33925d9e58b5c8d59308a760f4adea8f282370e428c51212c26633` |
| `face_detection_short_range.tflite` | 229032 | `3bc182eb9f33925d9e58b5c8d59308a760f4adea8f282370e428c51212c26633` |
| `face_detection_full_range.tflite` | 1083984 | `99bf9494d84f50acc6617d89873f71bf6635a841ea699c17cb3377f9507cfec3` |
| `face_detection_full_range_sparse.tflite` | 680736 | `671dd2f9ed11a78436fc21cc42357a803dfc6f73e9fb86541be942d5716c2dce` |
| `face_landmark.tflite` | 2439440 | `2efcb4f4de43c7614b80a3cc3e8a37354b3b3b40f75cce20f6f38f0f25d65493` |
| `iris_landmark.tflite` | 2640568 | `d1744d2a09c25f501d39eba4faff47e53ecca8852c5ce19bce8eeac39357521f` |
| `face_blendshapes.tflite` | 955312 | `4f36dded049db18d76048567439b2a7f58f1daabc00d78bfe8f3ad396a2d2082` |
| `mobilefacenet.tflite` | 5233552 | `be4bc7cfc53f7bc336d0f28b1ab92535f618c913a422b683210750f6b5354854` |
| `selfie_multiclass.tflite` | 16371837 | `c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0` |
| `selfie_segmenter.tflite` | 249537 | `191ac9529ae506ee0beefa6b2c945a172dab9d07d1e802a290a4e4038226658b` |
| `selfie_segmenter_landscape.tflite` | 250177 | `490e9ea734313e0de10fa0cd9e3c6133e36ea4db2b7a49bde9ef019f72796b8e` |

The upstream distribution declares these models Apache-2.0. Most are described
as Google MediaPipe assets in its model table. The exception is the
MobileFaceNet-derived embedding binary. Its introducing commit does not record
the original checkpoint, weight owner, training data, conversion steps, or a
separate model licence. The introducing upstream commit is
[`75b2ca733f40d0fc7933d5bb1d333439040ce64b`](https://github.com/hugocornellier/face_detection_tflite/commit/75b2ca733f40d0fc7933d5bb1d333439040ce64b).
Consequently, this project does **not** currently
represent that the embedding binary is cleared for commercial redistribution.
See [MODEL_CARD.md](MODEL_CARD.md) and
[the provenance request](doc/legal/model-provenance-request.md).

## Papers and names

MobileFaceNets is described in Sheng Chen, Yang Liu, Xiang Gao, and Zhen Han,
“MobileFaceNets: Efficient CNNs for Accurate Real-Time Face Verification on
Mobile Devices” (2018), <https://arxiv.org/abs/1804.07573>. A paper describes an
architecture; it does not license an independently trained checkpoint.

All product and project names remain the property of their respective owners.
No endorsement is implied.
