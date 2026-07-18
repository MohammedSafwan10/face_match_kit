# face_match_kit example

This application demonstrates guided three-pose enrollment, versioned template
creation, randomized basic liveness, 1:1 verification, retry, and explicit
template deletion. Templates remain in memory; the example does not upload or
persist biometric data.

Run it on a physical Android or iOS device:

```sh
flutter pub get
flutter run
```

Camera permission declarations are included in the example platform projects.
Basic liveness is a convenience barrier and is not presentation-attack-proof.
