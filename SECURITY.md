# Security and privacy

## Reporting

Report vulnerabilities through the repository's
[private security advisory form](https://github.com/MohammedSafwan10/face_match_kit/security/advisories/new)
before opening a public issue. Include affected versions, reproduction steps,
and impact. Do not include biometric templates or captured faces in reports.

## Threat model

Face verification is one signal, not a complete authentication system. The
basic randomized blink/head-turn challenge can deter a static photograph but
may be defeated by replay, masks, injection, rooted devices, or camera hooking.
Use platform integrity signals, rate limits, audit logs, and stronger
presentation-attack detection for high-risk actions.

## Template handling

- Treat serialized templates as sensitive biometric data.
- Protect them in transit and at rest with authenticated encryption (or a
  separately verified MAC/signature) using application-controlled keys.
- Never log embeddings, templates, or captured images.
- Bind templates to the correct account, tenant, schema version, and revocation
  state; prevent rollback to an older template.
- Provide consent, revocation, deletion, and retention controls.
- Reject templates whose schema, model hash, or pipeline version differs.
- Re-enroll rather than attempting to convert an embedding without source images.

Camera widgets do not upload data and make a best-effort attempt to delete each
temporary capture after it is read. Operating-system/plugin behavior can make
deletion unverifiable, and managed-memory image bytes are not guaranteed to be
zeroized before garbage collection. A host application that saves images or
templates assumes responsibility for that storage.
