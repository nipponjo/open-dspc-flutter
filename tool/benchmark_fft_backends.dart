import 'dart:convert';
import 'dart:io';

const _backends = <String>['pffft', 'kissfft'];

final class BenchRow {
  const BenchRow({
    required this.library,
    required this.function,
    required this.nfft,
    required this.warmup,
    required this.iterations,
    required this.usPerIter,
  });

  final String library;
  final String function;
  final int nfft;
  final int warmup;
  final int iterations;
  final double usPerIter;
}

Future<void> main(List<String> args) async {
  final outDir = args.isNotEmpty ? Directory(args.first) : Directory('bench');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  final root = Directory.current;
  final dart = Platform.resolvedExecutable;
  final results = <String, List<BenchRow>>{};

  stdout.writeln('Benchmarking FFT backends using bench/fft_bench.dart');
  stdout.writeln('Output directory: ${outDir.path}');

  for (final backend in _backends) {
    stdout.writeln('');
    stdout.writeln('== $backend ==');
    await _clearNativeAssetCaches();

    final csvPath =
        '${outDir.path}${Platform.pathSeparator}fft_bench_results_$backend.csv';
    final proc = await Process.start(
      dart,
      ['run', 'bench/fft_bench.dart', csvPath],
      workingDirectory: root.path,
      environment: <String, String>{
        ...Platform.environment,
        'OPENDSPC_FFT_BACKEND': backend,
      },
      mode: ProcessStartMode.inheritStdio,
    );

    final exitCode = await proc.exitCode;
    if (exitCode != 0) {
      throw ProcessException(
        dart,
        ['run', 'bench/fft_bench.dart', csvPath],
        'Benchmark run failed for backend $backend',
        exitCode,
      );
    }

    results[backend] = await _readCsv(csvPath);
  }

  final summaryPath =
      '${outDir.path}${Platform.pathSeparator}fft_bench_compare.json';
  final summary = _buildSummary(results);
  await File(
    summaryPath,
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(summary));

  stdout.writeln('');
  stdout.writeln('Comparison summary');
  _printComparison(results);
  stdout.writeln('');
  stdout.writeln('Wrote comparison JSON to $summaryPath');
}

Future<void> _clearNativeAssetCaches() async {
  final targets = <String>[
    '.dart_tool/native_assets',
    '.dart_tool/hooks_runner',
    '.dart_tool/test',
    '.dart_tool/native_assets.yaml',
  ];

  for (final path in targets) {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else if (type == FileSystemEntityType.file) {
      await File(path).delete();
    }
  }
}

Future<List<BenchRow>> _readCsv(String path) async {
  final lines = await File(path).readAsLines();
  if (lines.length <= 1) return const [];

  return lines
      .skip(1)
      .where((line) => line.trim().isNotEmpty)
      .map((line) {
        final parts = line.split(',');
        return BenchRow(
          library: parts[0],
          function: parts[1],
          nfft: int.parse(parts[2]),
          warmup: int.parse(parts[3]),
          iterations: int.parse(parts[4]),
          usPerIter: double.parse(parts[5]),
        );
      })
      .toList(growable: false);
}

Map<String, Object> _buildSummary(Map<String, List<BenchRow>> results) {
  final pffft = results['pffft'] ?? const <BenchRow>[];
  final kissfft = results['kissfft'] ?? const <BenchRow>[];
  final kissByKey = <String, BenchRow>{
    for (final row in kissfft) _key(row): row,
  };

  final comparisons = <Map<String, Object>>[];
  for (final row in pffft) {
    final other = kissByKey[_key(row)];
    if (other == null) continue;

    comparisons.add({
      'library': row.library,
      'function': row.function,
      'nfft': row.nfft,
      'pffft_us_per_iter': row.usPerIter,
      'kissfft_us_per_iter': other.usPerIter,
      'kissfft_div_pffft': other.usPerIter / row.usPerIter,
    });
  }

  return {
    'generated_at_utc': DateTime.now().toUtc().toIso8601String(),
    'comparisons': comparisons,
  };
}

void _printComparison(Map<String, List<BenchRow>> results) {
  final pffft = results['pffft'] ?? const <BenchRow>[];
  final kissfft = results['kissfft'] ?? const <BenchRow>[];
  final kissByKey = <String, BenchRow>{
    for (final row in kissfft) _key(row): row,
  };

  stdout.writeln(
    'function'.padRight(28) +
        'nfft'.padLeft(10) +
        'pffft(us)'.padLeft(14) +
        'kissfft(us)'.padLeft(14) +
        'kiss/pffft'.padLeft(14),
  );

  for (final row in pffft) {
    final other = kissByKey[_key(row)];
    if (other == null) continue;

    stdout.writeln(
      row.function.padRight(28) +
          row.nfft.toString().padLeft(10) +
          row.usPerIter.toStringAsFixed(3).padLeft(14) +
          other.usPerIter.toStringAsFixed(3).padLeft(14) +
          (other.usPerIter / row.usPerIter).toStringAsFixed(2).padLeft(14),
    );
  }
}

String _key(BenchRow row) => '${row.library}::${row.function}::${row.nfft}';
