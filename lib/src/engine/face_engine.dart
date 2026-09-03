import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_litert/native.dart';
import 'package:image/image.dart' as img;
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../face_camera_input.dart';
import 'image_preprocessor.dart';

const _blendshapeSubset = <int>[
  0,
  1,
  4,
  5,
  6,
  7,
  8,
  10,
  13,
  14,
  17,
  21,
  33,
  37,
  39,
  40,
  46,
  52,
  53,
  54,
  55,
  58,
  61,
  63,
  65,
  66,
  67,
  70,
  78,
  80,
  81,
  82,
  84,
  87,
  88,
  91,
  93,
  95,
  103,
  105,
  107,
  109,
  127,
  132,
  133,
  136,
  144,
  145,
  146,
  148,
  149,
  150,
  152,
  153,
  154,
  155,
  157,
  158,
  159,
  160,
  161,
  162,
  163,
  168,
  172,
  173,
  176,
  178,
  181,
  185,
  191,
  195,
  197,
  234,
  246,
  249,
  251,
  263,
  267,
  269,
  270,
  276,
  282,
  283,
  284,
  285,
  288,
  291,
  293,
  295,
  296,
  297,
  300,
  308,
  310,
  311,
  312,
  314,
  317,
  318,
  321,
  323,
  324,
  332,
  334,
  336,
  338,
  356,
  361,
  362,
  365,
  373,
  374,
  375,
  377,
  378,
  379,
  380,
  381,
  382,
  384,
  385,
  386,
  387,
  388,
  389,
  390,
  397,
  398,
  400,
  402,
  405,
  409,
  415,
  454,
  466,
  468,
  469,
  470,
  471,
  472,
  473,
  474,
  475,
  476,
  477,
];

class FaceEngine {
  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _events;
  final Stream<Object?> _eventStream;
  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  int _nextId = 0;
  bool _disposed = false;
  bool _liveInFlight = false;
  _PendingLive? _latestLive;

  FaceEngine._(this._isolate, this._commands, this._events, this._eventStream) {
    _eventStream.listen(_handleEvent);
  }

  static Future<FaceEngine> create({
    required Uint8List yunet,
    required Uint8List landmarks,
    required Uint8List blendshapes,
    required String sfacePath,
    required int maximumInputBytes,
    required int maximumImagePixels,
    required int canonicalMaxDimension,
  }) async {
    final events = ReceivePort();
    final eventStream = events.asBroadcastStream();
    final ready = Completer<SendPort>();
    late final StreamSubscription<Object?> subscription;
    subscription = eventStream.listen((message) {
      if (message is SendPort && !ready.isCompleted) ready.complete(message);
      if (message is Map && message['fatal'] != null && !ready.isCompleted) {
        ready.completeError(StateError(message['fatal']! as String));
      }
    });
    final isolate = await Isolate.spawn<Object?>(_workerMain, {
      'events': events.sendPort,
      'yunet': TransferableTypedData.fromList([yunet]),
      'landmarks': TransferableTypedData.fromList([landmarks]),
      'blendshapes': TransferableTypedData.fromList([blendshapes]),
      'sfacePath': sfacePath,
      'maximumInputBytes': maximumInputBytes,
      'maximumImagePixels': maximumImagePixels,
      'canonicalMaxDimension': canonicalMaxDimension,
    });
    try {
      final commands = await ready.future.timeout(const Duration(seconds: 20));
      await subscription.cancel();
      final engine = FaceEngine._(isolate, commands, events, eventStream);
      return engine;
    } catch (_) {
      isolate.kill(priority: Isolate.immediate);
      events.close();
      rethrow;
    }
  }

  Future<Map<String, Object?>> analyzeStill(
    Uint8List bytes, {
    required bool mirrored,
    required bool embedding,
  }) => _request({
    'type': 'still',
    'bytes': TransferableTypedData.fromList([bytes]),
    'mirrored': mirrored,
    'embedding': embedding,
  });

  Future<Map<String, Object?>?> analyzeLive(FaceCameraFrame frame) {
    if (_disposed) throw StateError('Face engine has been disposed.');
    final completer = Completer<Map<String, Object?>?>();
    final pending = _PendingLive(frame, completer);
    if (_liveInFlight) {
      _latestLive?.completer.complete(null);
      _latestLive = pending;
    } else {
      _dispatchLive(pending);
    }
    return completer.future;
  }

  void _dispatchLive(_PendingLive pending) {
    _liveInFlight = true;
    _request(_serializeFrame(pending.frame))
        .then(
          pending.completer.complete,
          onError: pending.completer.completeError,
        )
        .whenComplete(() {
          _liveInFlight = false;
          final next = _latestLive;
          _latestLive = null;
          if (next != null && !_disposed) _dispatchLive(next);
        });
  }

  Map<String, Object?> _serializeFrame(FaceCameraFrame frame) => {
    'type': 'live',
    'width': frame.width,
    'height': frame.height,
    'format': frame.format.name,
    'rotation': frame.rotation.index,
    'mirrored': frame.mirrored,
    'planes': [
      for (final plane in frame.planes)
        {
          'bytes': TransferableTypedData.fromList([plane.bytes]),
          'bytesPerRow': plane.bytesPerRow,
          'bytesPerPixel': plane.bytesPerPixel,
        },
    ],
  };

  Future<Map<String, Object?>> _request(Map<String, Object?> command) {
    if (_disposed) throw StateError('Face engine has been disposed.');
    final id = ++_nextId;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    command['id'] = id;
    _commands.send(command);
    return completer.future;
  }

  void _handleEvent(Object? event) {
    if (event is! Map) return;
    final id = event['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null) return;
    final error = event['error'];
    if (error is String) {
      completer.completeError(StateError(error));
    } else {
      completer.complete(Map<String, Object?>.from(event['result']! as Map));
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _latestLive?.completer.complete(null);
    _latestLive = null;
    final id = ++_nextId;
    final done = Completer<Map<String, Object?>>();
    _pending[id] = done;
    _commands.send({'id': id, 'type': 'dispose'});
    try {
      await done.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      // The isolate is terminated below even if native cleanup stalls.
    }
    _isolate.kill(priority: Isolate.immediate);
    _events.close();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Face engine was disposed.'));
      }
    }
    _pending.clear();
  }
}

class _PendingLive {
  final FaceCameraFrame frame;
  final Completer<Map<String, Object?>?> completer;
  _PendingLive(this.frame, this.completer);
}

Future<void> _workerMain(Object? initial) async {
  final args = Map<String, Object?>.from(initial! as Map);
  final events = args['events']! as SendPort;
  final commands = ReceivePort();
  _Worker? worker;
  try {
    worker = _Worker(
      yunet: _bytes(args['yunet']),
      landmarks: _bytes(args['landmarks']),
      blendshapes: _bytes(args['blendshapes']),
      sfacePath: args['sfacePath']! as String,
      maximumInputBytes: args['maximumInputBytes']! as int,
      maximumImagePixels: args['maximumImagePixels']! as int,
      canonicalMaxDimension: args['canonicalMaxDimension']! as int,
    );
    await worker.initialize();
    events.send(commands.sendPort);
  } catch (error) {
    events.send({'fatal': 'Face engine initialization failed: $error'});
    commands.close();
    return;
  }

  var tail = Future<void>.value();
  commands.listen((message) {
    tail = tail.then((_) async {
      final command = Map<String, Object?>.from(message! as Map);
      final id = command['id']! as int;
      try {
        final type = command['type'];
        if (type == 'dispose') {
          worker!.dispose();
          events.send({'id': id, 'result': <String, Object?>{}});
          commands.close();
          return;
        }
        final result = type == 'still'
            ? worker!.analyzeStill(
                _bytes(command['bytes']),
                mirrored: command['mirrored']! as bool,
                embedding: command['embedding']! as bool,
              )
            : worker!.analyzeLive(command);
        events.send({'id': id, 'result': result});
      } catch (error) {
        events.send({'id': id, 'error': '$error'});
      }
    });
  });
}

Uint8List _bytes(Object? value) =>
    (value! as TransferableTypedData).materialize().asUint8List();

class _Worker {
  final Uint8List yunet;
  final Uint8List landmarks;
  final Uint8List blendshapes;
  final String sfacePath;
  final int maximumInputBytes;
  final int maximumImagePixels;
  final int canonicalMaxDimension;

  late final cv.FaceDetectorYN _detector;
  late final cv.FaceRecognizerSF _recognizer;
  late final Interpreter _landmarkInterpreter;
  late final Interpreter _blendshapeInterpreter;
  late final TensorFloat32Views _landmarkViews;
  late final TensorFloat32Views _blendshapeViews;

  _Worker({
    required this.yunet,
    required this.landmarks,
    required this.blendshapes,
    required this.sfacePath,
    required this.maximumInputBytes,
    required this.maximumImagePixels,
    required this.canonicalMaxDimension,
  });

  Future<void> initialize() async {
    cv.FaceDetectorYN? detector;
    cv.FaceRecognizerSF? recognizer;
    Interpreter? landmarkInterpreter;
    Interpreter? blendshapeInterpreter;
    try {
      detector = cv.FaceDetectorYN.fromBuffer(
        'onnx',
        yunet,
        Uint8List(0),
        (320, 320),
        scoreThreshold: 0.5,
        nmsThreshold: 0.3,
        topK: 16,
      );
      recognizer = cv.FaceRecognizerSF.fromFile(sfacePath, '');
      landmarkInterpreter = Interpreter.fromBuffer(landmarks);
      landmarkInterpreter.allocateTensors();
      blendshapeInterpreter = Interpreter.fromBuffer(blendshapes);
      blendshapeInterpreter.allocateTensors();
      _detector = detector;
      _recognizer = recognizer;
      _landmarkInterpreter = landmarkInterpreter;
      _landmarkViews = TensorFloat32Views.capture(landmarkInterpreter);
      _blendshapeInterpreter = blendshapeInterpreter;
      _blendshapeViews = TensorFloat32Views.capture(blendshapeInterpreter);
    } catch (_) {
      blendshapeInterpreter?.close();
      landmarkInterpreter?.close();
      recognizer?.dispose();
      detector?.dispose();
      rethrow;
    }
  }

  Map<String, Object?> analyzeStill(
    Uint8List encoded, {
    required bool mirrored,
    required bool embedding,
  }) {
    final image = canonicalStillImage(
      encoded,
      mirrored: mirrored,
      maximumInputBytes: maximumInputBytes,
      maximumImagePixels: maximumImagePixels,
      maximumDimension: canonicalMaxDimension,
    );
    return _analyze(image, embedding: embedding);
  }

  Map<String, Object?> analyzeLive(Map<String, Object?> command) {
    var image = _cameraImage(command);
    final rotation = FaceCameraRotation.values[command['rotation']! as int];
    image = switch (rotation) {
      FaceCameraRotation.none => image,
      FaceCameraRotation.clockwise90 => img.copyRotate(image, angle: 90),
      FaceCameraRotation.clockwise180 => img.copyRotate(image, angle: 180),
      FaceCameraRotation.clockwise270 => img.copyRotate(image, angle: 270),
    };
    if (command['mirrored']! as bool) image = img.flipHorizontal(image);
    image = resizeImage(image, 640);
    return _analyze(image, embedding: false);
  }

  Map<String, Object?> _analyze(img.Image image, {required bool embedding}) {
    final bgr = _toBgrMat(image);
    cv.Mat? detections;
    try {
      _detector.setInputSize((image.width, image.height));
      detections = _detector.detect(bgr);
      if (detections.isEmpty) return {'faces': <Object?>[]};
      final rows = detections.toList().take(2).toList(growable: false);
      final faces = <Map<String, Object?>>[];
      for (final raw in rows) {
        final row = raw
            .map((value) => value.toDouble())
            .toList(growable: false);
        faces.add(_faceResult(image, row, runGuidance: rows.length == 1));
      }
      final result = <String, Object?>{'faces': faces};
      if (embedding && rows.length == 1) {
        final row = rows.single.map((value) => value.toDouble()).toList();
        final faceBox = cv.Mat.fromList(1, 15, cv.MatType.CV_32FC1, row);
        cv.Mat? aligned;
        cv.Mat? feature;
        try {
          aligned = _recognizer.alignCrop(bgr, faceBox);
          feature = _recognizer.feature(aligned, clone: true);
          final flat = feature
              .toList()
              .expand((values) => values)
              .map((value) => value.toDouble())
              .toList(growable: false);
          if (flat.length != 128 || flat.any((value) => !value.isFinite)) {
            throw StateError('SFace returned an invalid feature vector.');
          }
          result['embedding'] = _normalize(flat);
        } finally {
          feature?.dispose();
          aligned?.dispose();
          faceBox.dispose();
        }
      }
      return result;
    } finally {
      detections?.dispose();
      bgr.dispose();
    }
  }

  Map<String, Object?> _faceResult(
    img.Image image,
    List<double> row, {
    required bool runGuidance,
  }) {
    final x = row[0];
    final y = row[1];
    final width = row[2];
    final height = row[3];
    final rightEye = (x: row[4], y: row[5]);
    final leftEye = (x: row[6], y: row[7]);
    final roll =
        math.atan2(leftEye.y - rightEye.y, leftEye.x - rightEye.x) *
        180 /
        math.pi;
    final landmark = runGuidance ? _runLandmarks(image, row) : null;
    return {
      'box': [
        x / image.width,
        y / image.height,
        (x + width) / image.width,
        (y + height) / image.height,
      ],
      'score': row[14].clamp(0, 1),
      'faceFraction': width / image.width,
      'pitch': landmark?.pitch,
      'yaw': landmark?.yaw,
      'roll': roll,
      'leftEyeOpenProbability': landmark?.leftEyeOpen,
      'rightEyeOpenProbability': landmark?.rightEyeOpen,
    };
  }

  ({double yaw, double pitch, double leftEyeOpen, double rightEyeOpen})?
  _runLandmarks(img.Image image, List<double> row) {
    const side = 256;
    final tensor = Float32List(side * side * 3);
    final cx = row[0] + row[2] / 2;
    final cy = row[1] + row[3] / 2;
    final cropSide = math.max(row[2], row[3]) * 1.5;
    final angle = math.atan2(row[7] - row[5], row[6] - row[4]);
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    var offset = 0;
    for (var oy = 0; oy < side; oy++) {
      final dy = ((oy + 0.5) / side - 0.5) * cropSide;
      for (var ox = 0; ox < side; ox++) {
        final dx = ((ox + 0.5) / side - 0.5) * cropSide;
        final sx = cx + cosA * dx - sinA * dy;
        final sy = cy + sinA * dx + cosA * dy;
        if (sx >= 0 && sx < image.width && sy >= 0 && sy < image.height) {
          final pixel = image.getPixelInterpolate(
            sx,
            sy,
            interpolation: img.Interpolation.linear,
          );
          tensor[offset] = pixel.r / 255.0;
          tensor[offset + 1] = pixel.g / 255.0;
          tensor[offset + 2] = pixel.b / 255.0;
        }
        offset += 3;
      }
    }
    _landmarkViews.inputs[0].setAll(0, tensor);
    _landmarkInterpreter.invoke();
    final raw = _landmarkViews.outputs.first;
    if (raw.length != 1434) return null;
    final score = _sigmoid(_landmarkViews.outputs[1][0]);
    if (score < 0.5) return null;
    final points = List<(double, double)>.generate(478, (index) {
      final dx = (raw[index * 3] / side - 0.5) * cropSide;
      final dy = (raw[index * 3 + 1] / side - 0.5) * cropSide;
      return (cx + cosA * dx - sinA * dy, cy + sinA * dx + cosA * dy);
    }, growable: false);
    final blendInput = Float32List(146 * 2);
    var write = 0;
    for (final index in _blendshapeSubset) {
      blendInput[write++] = points[index].$1;
      blendInput[write++] = points[index].$2;
    }
    _blendshapeViews.inputs[0].setAll(0, blendInput);
    _blendshapeInterpreter.invoke();
    final blend = _blendshapeViews.outputs.first;
    final leftOpen = (1.0 - blend[9]).clamp(0.0, 1.0);
    final rightOpen = (1.0 - blend[10]).clamp(0.0, 1.0);
    final eyeMidX = (points[33].$1 + points[263].$1) / 2;
    final eyeMidY = (points[33].$2 + points[263].$2) / 2;
    final eyeDistance = math.max(1.0, (points[263].$1 - points[33].$1).abs());
    final mouthY = (points[61].$2 + points[291].$2) / 2;
    final yaw = ((points[1].$1 - eyeMidX) / eyeDistance * 90).clamp(-60, 60);
    final vertical = math.max(1.0, mouthY - eyeMidY);
    final pitch = (((points[1].$2 - eyeMidY) / vertical) - 0.52) * 80;
    return (
      yaw: yaw.toDouble(),
      pitch: pitch.clamp(-45, 45).toDouble(),
      leftEyeOpen: leftOpen.toDouble(),
      rightEyeOpen: rightOpen.toDouble(),
    );
  }

  img.Image _cameraImage(Map<String, Object?> command) {
    final width = command['width']! as int;
    final height = command['height']! as int;
    final planes = (command['planes']! as List)
        .map((value) => Map<String, Object?>.from(value as Map))
        .toList();
    final image = img.Image(width: width, height: height, numChannels: 3);
    if (command['format'] == FaceCameraPixelFormat.bgra8888.name) {
      final plane = planes.first;
      final bytes = _bytes(plane['bytes']);
      final rowStride = plane['bytesPerRow']! as int;
      final pixelStride = plane['bytesPerPixel']! as int;
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final index = y * rowStride + x * pixelStride;
          image.setPixelRgb(
            x,
            y,
            bytes[index + 2],
            bytes[index + 1],
            bytes[index],
          );
        }
      }
      return image;
    }
    final yPlane = planes[0];
    final uPlane = planes[1];
    final vPlane = planes[2];
    final yBytes = _bytes(yPlane['bytes']);
    final uBytes = _bytes(uPlane['bytes']);
    final vBytes = _bytes(vPlane['bytes']);
    final yRow = yPlane['bytesPerRow']! as int;
    final uRow = uPlane['bytesPerRow']! as int;
    final vRow = vPlane['bytesPerRow']! as int;
    final yPixel = yPlane['bytesPerPixel']! as int;
    final uPixel = uPlane['bytesPerPixel']! as int;
    final vPixel = vPlane['bytesPerPixel']! as int;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final yy = yBytes[y * yRow + x * yPixel].toDouble();
        final uu = uBytes[(y >> 1) * uRow + (x >> 1) * uPixel] - 128.0;
        final vv = vBytes[(y >> 1) * vRow + (x >> 1) * vPixel] - 128.0;
        final r = (yy + 1.402 * vv).round().clamp(0, 255);
        final g = (yy - 0.344136 * uu - 0.714136 * vv).round().clamp(0, 255);
        final b = (yy + 1.772 * uu).round().clamp(0, 255);
        image.setPixelRgb(x, y, r, g, b);
      }
    }
    return image;
  }

  cv.Mat _toBgrMat(img.Image image) {
    return cv.Mat.fromList(
      image.height,
      image.width,
      cv.MatType.CV_8UC3,
      bgrBytes(image),
    );
  }

  void dispose() {
    _blendshapeInterpreter.close();
    _landmarkInterpreter.close();
    _recognizer.dispose();
    _detector.dispose();
    try {
      File(sfacePath).deleteSync();
    } catch (_) {
      // Temporary-file cleanup is best effort.
    }
  }
}

List<double> _normalize(List<double> values) {
  final norm = math.sqrt(values.fold<double>(0, (sum, v) => sum + v * v));
  if (!norm.isFinite || norm <= 1e-12) {
    throw StateError('SFace returned a zero-length feature vector.');
  }
  return [for (final value in values) value / norm];
}

double _sigmoid(double value) {
  if (value >= 20) return 1;
  if (value <= -20) return 0;
  return 1 / (1 + math.exp(-value));
}
