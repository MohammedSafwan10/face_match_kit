# Contributing

Thank you for helping improve `face_match_kit`. Open an issue before large API,
model, pipeline, or storage changes so compatibility and privacy consequences
can be discussed first.

## Development checks

Run these commands from the package root before submitting a pull request:

```sh
dart format --output=none --set-exit-if-changed lib test example/lib
flutter analyze
flutter test
dart pub publish --dry-run
```

Build the example for every platform affected by the change. Camera, liveness,
orientation, mirroring, and embedding changes require physical-device testing.

## Compatibility and security

- Do not change model bytes or preprocessing without changing the model or
  pipeline identifier and requiring re-enrollment.
- Do not add captured faces or biometric templates to tests, logs, fixtures, or
  pull requests without documented consent and retention controls.
- Keep routine failures typed and keep ML Kit/upstream types out of the public
  API.
- Do not describe basic blink/head-turn liveness as spoof-proof.
- Do not weaken the release gates in `MODEL_CARD.md` or `PUBLISHING.md`.

Report vulnerabilities privately as described in `SECURITY.md`.

By contributing, you agree that your contribution is licensed under
Apache-2.0.
