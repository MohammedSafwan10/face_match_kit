import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_litert/flutter_litert.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled model assets have the release hashes', () async {
    const expected = <String, (int, String)>{
      'face_detection_yunet_2023mar.onnx': (
        232589,
        '8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4',
      ),
      'face_recognition_sface_2021dec_int8.onnx': (
        9896933,
        '2b0e941e6f16cc048c20aee0c8e31f569118f65d702914540f7bfdc14048d78a',
      ),
      'face_landmarks_detector.tflite': (
        2553590,
        'c7d54204ce0448474c7f3fa9af494787c0965cbdd6f20fc72867e43046bd43d5',
      ),
      'face_blendshapes.tflite': (
        955312,
        '4f36dded049db18d76048567439b2a7f58f1daabc00d78bfe8f3ad396a2d2082',
      ),
    };
    for (final entry in expected.entries) {
      final data = await rootBundle.load('assets/models/${entry.key}');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      expect(bytes.length, entry.value.$1, reason: entry.key);
      expect(
        sha256.convert(bytes).toString(),
        entry.value.$2,
        reason: entry.key,
      );
    }
  });

  test(
    'MediaPipe guidance models expose the pinned tensor contracts',
    () async {
      final landmarkData = await rootBundle.load(
        'assets/models/face_landmarks_detector.tflite',
      );
      final landmark = Interpreter.fromBuffer(
        landmarkData.buffer.asUint8List(),
      );
      landmark.allocateTensors();
      expect(landmark.getInputTensor(0).shape, [1, 256, 256, 3]);
      expect(landmark.getOutputTensor(0).shape, [1, 1, 1, 1434]);
      landmark.close();

      final blendData = await rootBundle.load(
        'assets/models/face_blendshapes.tflite',
      );
      final blend = Interpreter.fromBuffer(blendData.buffer.asUint8List());
      blend.allocateTensors();
      expect(blend.getInputTensor(0).shape, [1, 146, 2]);
      expect(blend.getOutputTensor(0).shape, [52]);
      blend.close();
    },
  );
}
