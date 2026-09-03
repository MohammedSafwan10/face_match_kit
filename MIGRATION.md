# Migration guide

## Mandatory SFace re-enrollment

Every unversioned embedding and every schema-v1 package template belongs to the
removed 192-dimensional MobileFaceNet pipeline. It is incompatible with SFace
schema v2 and must be re-enrolled once.

## From an unversioned embedding

An old `List<double>` does not identify the model, alignment, mirroring,
normalization, or threshold that created it. Do not wrap it in a new
`FaceTemplate`.

1. Detect the old `embedding` field only as a marker. Do not deserialize,
   archive, compare, or upload its vector values.
2. Mark the account as requiring biometric re-enrollment.
3. Guide the user through front, slight-left, and slight-right capture.
4. Store `FaceTemplate.toJson()` as one atomic record.
5. Atomically overwrite the current record, removing the old vector, and
   invalidate every legacy device cache.

## Template upgrades

Any change to model bytes or preprocessing increments the package constants.
Verification returns `FaceMatchErrorCode.incompatibleTemplate` until the user
re-enrolls. Never silently lower thresholds to make incompatible templates pass.
