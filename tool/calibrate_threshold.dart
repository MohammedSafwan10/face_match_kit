import 'dart:io';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/calibrate_threshold.dart scores.csv');
    exitCode = 64;
    return;
  }
  final rows = File(args.single).readAsLinesSync().skip(1);
  final genuine = <double>[];
  final impostor = <double>[];
  for (final row in rows) {
    final columns = row.split(',');
    if (columns.length != 2) continue;
    final score = double.tryParse(columns[1].trim());
    if (score == null) continue;
    switch (columns[0].trim().toLowerCase()) {
      case 'genuine':
        genuine.add(score);
      case 'impostor':
        impostor.add(score);
    }
  }
  if (genuine.isEmpty || impostor.isEmpty) {
    stderr.writeln('CSV must contain genuine and impostor rows.');
    exitCode = 65;
    return;
  }
  stdout.writeln('threshold,FAR,FRR');
  for (var threshold = 0.40; threshold <= 0.80; threshold += 0.01) {
    final falseAccepts = impostor.where((score) => score >= threshold).length;
    final falseRejects = genuine.where((score) => score < threshold).length;
    final far = falseAccepts / impostor.length;
    final frr = falseRejects / genuine.length;
    stdout.writeln(
      '${threshold.toStringAsFixed(2)},${far.toStringAsFixed(6)},${frr.toStringAsFixed(6)}',
    );
  }
}
