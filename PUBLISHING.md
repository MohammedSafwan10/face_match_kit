# Publishing checklist

Do not run `dart pub publish` until every release gate below is complete.

- [ ] Confirm the embedding model's original weight owner, checkpoint source,
      training-data terms, conversion process, and redistribution licence in
      writing, or replace it with fully documented redistributable weights.
- [x] Record the exact upstream commit that introduced the embedding model and
      provide a reproducible written provenance request under `doc/legal/`.
- [x] Inventory all twelve model assets redistributed by the transitive face
      dependency, including byte sizes and SHA-256 values.
- [x] Record and verify all five pipeline asset SHA-256 values at package
      initialization and bind them to the pipeline identifier.
- [ ] Pass formatting, analysis, unit tests, Android example build, and
      `dart pub publish --dry-run` with zero warnings.
- [ ] Pass API documentation generation. Dartdoc currently crashes in its own
      comment parser and remains a release blocker until resolved or fixed
      upstream.
- [ ] Pass the iOS no-codesign CI build on macOS.
- [ ] Complete Android→Android, Android→iOS, iOS→Android, and iOS→iOS tests on
      at least two Android and two iPhone models.
- [ ] Calibrate the default threshold from consenting genuine/impostor pairs
      and publish FAR/FRR by platform direction and supported conditions.
- [ ] Review privacy, biometric consent, deletion, retention, and incident
      obligations for intended launch regions.
- [x] Document package-level data processing and the host application's privacy
      and biometric-governance responsibilities in `PRIVACY.md`.
- [ ] Replace or validate upstream eye-only alignment against a documented
      canonical eyes-and-nose alignment implementation.
- [ ] Measure and reduce the release binary/native-model footprint.
- [x] Create the public repository URLs declared in `pubspec.yaml`.
- [ ] Publish from the verified `nexdark.com` pub.dev publisher only after all
      other gates are complete.

Version `0.1.0` must remain labelled beta. Do not publish `1.0.0` until the
accuracy and platform-specific failure criteria in `benchmark/README.md` pass.
