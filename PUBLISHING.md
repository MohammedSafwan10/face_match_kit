# Publishing checklist

`0.1.0` is published as a beta and transferred to the `nexdark.com`
publisher. The unchecked gates below remain open and must close before any
stable release or production-readiness claim.

- [x] Remove `face_detection_tflite`, MobileFaceNet, and unused transitive
      assets from the dependency graph and archive.
- [x] Record and verify byte sizes, hashes, immutable sources, and licences for
      SFace, YuNet, and the two MediaPipe models.
- [x] Include YuNet's full MIT notice and current third-party inventory.
- [x] Introduce strict schema-v2 templates and mandatory legacy re-enrollment.
- [ ] Obtain authoritative clarification for the exact SFace weight or record
      documented legal/business acceptance of residual training-data risk.
- [ ] Validate the custom MediaPipe ROI/landmark/blendshape preprocessing
      against official Face Landmarker outputs.
- [ ] Calibrate verification with FAR upper confidence bound <= 0.1% and
      FRR <= 5%; calibrate enrollment for >=95% valid acceptance and >=99.9%
      mixed-person rejection.
- [ ] Test equivalent fixtures and Android->Android, Android->iOS,
      iOS->Android, and iOS->iOS on at least two Android and two iPhone models.
- [ ] Add and pass the planned widget, lifecycle, timeout, queue, native
      inference, fixture, and cross-platform tests.
- [x] Pass format, analyze, unit/widget tests, dartdoc, pana/package score,
      and clean publish dry-run.
- [ ] Pass Android example build and iOS no-codesign example build in CI
      (currently red; `calib3d` added to example `include_modules`, awaiting
      verification).
- [x] Ensure `dart pub publish --dry-run` reports zero warnings.
- [x] Publish `0.1.0` with the authorized Google account and transfer it to
      the verified `nexdark.com` publisher in pub.dev administration.
- [ ] Replace pub screenshots with actual enrollment and verification UI.
- [ ] Review consent, retention, deletion, revocation, authenticated template
      storage, and biometric-law obligations for each launch region.

For a new package, publish with the authorized Google account first and then
transfer it to the verified `nexdark.com` publisher in pub.dev administration.
Do not claim production readiness, spoof resistance, or measured
cross-platform accuracy in this beta.
