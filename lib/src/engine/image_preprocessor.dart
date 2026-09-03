import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Decodes and canonicalizes one still image without native re-decoding.
img.Image canonicalStillImage(
  Uint8List encoded, {
  required bool mirrored,
  required int maximumInputBytes,
  required int maximumImagePixels,
  required int maximumDimension,
}) {
  if (encoded.isEmpty || encoded.length > maximumInputBytes) {
    throw const FormatException('Image exceeds the supported byte limit.');
  }
  final decoder = img.findDecoderForData(encoded);
  final info = decoder?.startDecode(encoded);
  if (decoder == null || info == null) {
    throw const FormatException('Unsupported image data.');
  }
  if (info.width <= 0 ||
      info.height <= 0 ||
      info.width * info.height > maximumImagePixels) {
    throw const FormatException('Image exceeds the supported pixel limit.');
  }
  var image = decoder.decode(encoded, frame: 0);
  if (image == null) throw const FormatException('Unsupported image data.');
  image = img.bakeOrientation(image);
  if (mirrored) image = img.flipHorizontal(image);
  return resizeImage(image, maximumDimension);
}

/// Deterministic longest-side resize used by the versioned pipeline.
img.Image resizeImage(img.Image image, int maximumDimension) {
  final longest = math.max(image.width, image.height);
  if (longest <= maximumDimension) return image;
  final scale = maximumDimension / longest;
  return img.copyResize(
    image,
    width: math.max(1, (image.width * scale).round()),
    height: math.max(1, (image.height * scale).round()),
    interpolation: img.Interpolation.linear,
  );
}

/// Converts canonical RGB pixels into tightly packed OpenCV BGR bytes.
Uint8List bgrBytes(img.Image image) {
  final bytes = Uint8List(image.width * image.height * 3);
  var offset = 0;
  for (final pixel in image) {
    bytes[offset++] = pixel.b.toInt();
    bytes[offset++] = pixel.g.toInt();
    bytes[offset++] = pixel.r.toInt();
  }
  return bytes;
}
