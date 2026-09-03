# Third-party software and model notices

This file records the runtime inventory for the `0.1.0` beta. It does not
replace licence files distributed by Flutter or resolved pub dependencies.

## Runtime software

| Component | Tested version | Licence | Purpose |
|---|---:|---|---|
| Flutter SDK | current supported SDK | BSD-style | UI and mobile runtime |
| `camera` | 0.12.x | BSD-3-Clause | Android/iOS camera |
| `crypto` | 3.0.x | BSD-3-Clause | SHA-256 checks |
| `flutter_litert` | 3.5.1 | Apache-2.0 | MediaPipe TFLite inference |
| `image` | 4.3.0 | MIT and bundled notices | deterministic Dart image processing |
| `opencv_dart` / `dartcv4` | 2.2.1+4 | Apache-2.0 | OpenCV native bindings/runtime |

## Bundled model assets

| Asset | Bytes | SHA-256 | Licence |
|---|---:|---|---|
| SFace INT8 | 9,896,933 | `2b0e941e6f16cc048c20aee0c8e31f569118f65d702914540f7bfdc14048d78a` | Apache-2.0 |
| YuNet 2023mar | 232,589 | `8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4` | MIT |
| MediaPipe face landmarks | 2,553,590 | `c7d54204ce0448474c7f3fa9af494787c0965cbdd6f20fc72867e43046bd43d5` | Apache-2.0 |
| MediaPipe face blendshapes | 955,312 | `4f36dded049db18d76048567439b2a7f58f1daabc00d78bfe8f3ad396a2d2082` | Apache-2.0 |

SFace is from OpenCV Zoo commit
`088c3571ec70df15100a5e4c26894d95951e92e9`. YuNet is from OpenCV Zoo
commit `f12e12798e8314f7c074a6656816c048dcc95b7a`. The MediaPipe files were
extracted from the official Face Landmarker `float16/1` task (3,758,596 bytes,
SHA-256 `64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff`).

The OpenCV and MediaPipe Apache-2.0 licence texts are available in their source
repositories and at <https://www.apache.org/licenses/LICENSE-2.0>.

## YuNet MIT licence

MIT License

Copyright (c) 2020 Shiqi Yu <shiqi.yu@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Risk note

OpenCV Zoo declares the exact SFace artifact Apache-2.0, but does not document
a complete checkpoint and training-data chain of title. See MODEL_CARD.md for
the commercial release decision required by this project.
