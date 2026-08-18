# SDK privacy information

This document describes `face_match_kit` itself. It is not a privacy policy for
an application that integrates the package and is not legal advice.

## What the package processes

- Live camera frames for face guidance and the basic liveness challenge.
- Still-image bytes for enrollment and 1:1 verification.
- Facial landmarks, quality measurements and face embeddings.
- A versioned `FaceTemplate` returned to the integrating application.

These are biometric operations. A template must be treated as sensitive
biometric data even though it is not a photograph.

## Network and retention behaviour

The package contains no upload, analytics, advertising or telemetry client.
Detection and inference run on the device. The low-level API does not persist
images or templates. Camera widgets read captures created by the camera plugin
and make a best-effort deletion attempt afterward. Operating-system caches,
plugin-managed files and managed-memory copies cannot be guaranteed to be
immediately erased or cryptographically zeroized.

The integrating application decides whether and where to store the returned
template. Consequently, the application developer is the party that must
document storage location, retention, access, sharing and deletion behaviour.

## Integrator requirements

Before enabling enrollment or verification, an integrating application should:

1. Give a clear biometric notice and obtain the consent or other legal basis
   required in every launch jurisdiction.
2. Explain the purpose of processing, retention period, deletion process,
   recipients, cross-border transfers and the consequences of declining.
3. Protect stored templates with authenticated encryption or an independently
   verified signature/MAC, bind them to the correct user and tenant, and prevent
   rollback to revoked templates.
4. Provide deletion, revocation and re-enrollment controls and honor applicable
   access/correction/appeal rights.
5. Keep images and templates out of logs, crash reports, analytics and test
   fixtures unless separately justified and protected.
6. Establish incident-response, breach-notification and retention procedures.
7. Perform security, accuracy and demographic-performance testing appropriate
   to the application's risk and supported population.
8. Complete the Apple privacy manifest/App Store disclosures and Google Play
   Data safety form based on the **whole application**, including its storage,
   backend and other SDKs. This package document cannot answer those forms for
   the host application.

High-risk uses such as surveillance, law enforcement, employment decisions or
unsupervised access to critical systems are outside the package's validated
scope. Basic blink/head-turn liveness is not presentation-attack detection.
