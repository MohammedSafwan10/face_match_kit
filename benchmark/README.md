# Accuracy and portability protocol

Do not use HRM production templates or images for package benchmarking. Recruit
consenting participants, assign anonymous identifiers, encrypt captures during
the study, and delete them at the agreed retention deadline.

For each candidate release:

1. Use at least two Android and two iPhone models.
2. Enroll each participant on both platforms with the packaged three-pose flow.
3. Capture genuine probes under supported lighting, distance, glasses, and pose.
4. Compare each probe with its owner and with other participants to produce
   genuine and impostor score sets.
5. Report FAR and FRR for every candidate threshold and separately for
   Android→Android, Android→iOS, iOS→Android, and iOS→iOS.
6. Record p50/p95 initialization, detection, enrollment, and verification time.
7. Do not publish a production claim until cross-platform results show no
   unexplained platform-specific score shift.

`tool/calibrate_threshold.dart` accepts a CSV containing `label,score`, where
label is `genuine` or `impostor`, and prints candidate FAR/FRR values.
