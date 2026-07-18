import 'dart:convert';

import 'package:face_match_kit/face_match_kit.dart';
import 'package:flutter/material.dart';

void main() => runApp(const FaceMatchExampleApp());

class FaceMatchExampleApp extends StatelessWidget {
  const FaceMatchExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Face Match Kit',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0284C7),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: const FaceMatchDemo(),
  );
}

class FaceMatchDemo extends StatefulWidget {
  const FaceMatchDemo({super.key});

  @override
  State<FaceMatchDemo> createState() => _FaceMatchDemoState();
}

class _FaceMatchDemoState extends State<FaceMatchDemo> {
  FaceTemplate? _template;
  String? _serializedTemplate;
  String _status = 'Enroll a face to begin.';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Face Match Kit'),
      actions: [
        if (_template != null)
          IconButton(
            tooltip: 'Delete demo template',
            onPressed: () => setState(() {
              _template = null;
              _serializedTemplate = null;
              _status = 'Template deleted from memory.';
            }),
            icon: const Icon(Icons.delete_outline),
          ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: _template == null
                ? FaceEnrollmentView(
                    onCompleted: (result) {
                      setState(() {
                        _template = result.template;
                        _serializedTemplate = result.template == null
                            ? null
                            : jsonEncode(result.template!.toJson());
                        _status = result.isSuccess
                            ? 'Enrollment complete. Template kept in memory.'
                            : result.failure?.message ?? 'Enrollment failed.';
                      });
                    },
                  )
                : FaceVerificationView(
                    template: _template!,
                    onCompleted: (result) {
                      setState(() {
                        _status = result.isMatch
                            ? 'Verified at ${(result.similarity * 100).toStringAsFixed(1)}% similarity.'
                            : result.failure?.message ?? 'No match.';
                      });
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(_status, textAlign: TextAlign.center),
                if (_serializedTemplate != null)
                  Text(
                    'Serialized template: ${_serializedTemplate!.length} bytes',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
