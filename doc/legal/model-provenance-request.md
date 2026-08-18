# MobileFaceNet model provenance request

Send the following request to the maintainer of `face_detection_tflite` before
publishing `face_match_kit`. Preserve the response and linked evidence in the
release records; a statement about the source-code repository licence alone is
not sufficient.

> We depend on `face_detection_tflite` 6.6.3 and need to redistribute the exact
> `assets/models/mobilefacenet.tflite` binary in commercial Android/iOS apps.
> The file is 5,233,552 bytes with SHA-256
> `be4bc7cfc53f7bc336d0f28b1ab92535f618c913a422b683210750f6b5354854`.
>
> Please provide:
>
> 1. The original repository/download URL and immutable commit or checkpoint.
> 2. The checkpoint owner and the identity of the person/entity granting its
>    licence.
> 3. The model-weight licence text that permits modification, commercial use
>    and redistribution of this exact binary.
> 4. The training dataset(s), their terms, and confirmation that the resulting
>    weights may be commercially redistributed.
> 5. The conversion path and commands used to create this TFLite file.
> 6. Any attribution, notice, acceptable-use or field-of-use requirements.
> 7. Confirmation that the Apache-2.0 declaration is intended to cover this
>    exact model binary, not only the surrounding source code.

If this evidence cannot be supplied, replace the embedding model. Any
replacement changes the model ID, hash, dimensions and pipeline version,
invalidates existing templates, requires re-enrollment, and must be calibrated
and tested again on Android and iOS.
