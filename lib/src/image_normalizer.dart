import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

Future<Uint8List> canonicalizeImage(Uint8List bytes, {bool mirrored = false}) =>
    compute(_canonicalizeImage, (bytes: bytes, mirrored: mirrored));

Uint8List _canonicalizeImage(({Uint8List bytes, bool mirrored}) input) {
  final decoded = img.decodeImage(input.bytes);
  if (decoded == null) throw const FormatException('Unsupported image data.');
  var canonical = img.bakeOrientation(decoded);
  if (input.mirrored) canonical = img.flipHorizontal(canonical);
  // Lossless PNG ensures that host dependency resolution cannot introduce
  // JPEG quantization differences into otherwise identical face pixels.
  return Uint8List.fromList(img.encodePng(canonical, level: 0));
}
