# Migration guide

## From an unversioned embedding

An old `List<double>` does not identify the model, alignment, mirroring,
normalization, or threshold that created it. Do not wrap it in a new
`FaceTemplate`.

1. Detect the missing `schemaVersion`, `modelHash`, or `pipelineVersion`.
2. Mark the account as requiring biometric re-enrollment.
3. Guide the user through front, slight-left, and slight-right capture.
4. Store `FaceTemplate.toJson()` as one atomic record.
5. Delete the old vector and invalidate all device caches.

## Template upgrades

Any change to model bytes or preprocessing increments the package constants.
Verification returns `FaceMatchErrorCode.incompatibleTemplate` until the user
re-enrolls. Never silently lower thresholds to make incompatible templates pass.
