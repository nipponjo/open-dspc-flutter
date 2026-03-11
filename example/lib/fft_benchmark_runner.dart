import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart' as fftea;
import 'package:open_dspc/open_dspc.dart';
import 'package:path_provider/path_provider.dart';

typedef BenchFn = double Function();
typedef BenchmarkProgress = void Function(String message);

class BenchRow {
  final String libraryName;
  final String functionName;
  final int nfft;
  final int warmup;
  final int iterations;
  final double microsecondsPerIter;

  const BenchRow({
    required this.libraryName,
    required this.functionName,
    required this.nfft,
    required this.warmup,
    required this.iterations,
    required this.microsecondsPerIter,
  });

  String toCsv() {
    return [
      libraryName,
      functionName,
      nfft.toString(),
      warmup.toString(),
      iterations.toString(),
      microsecondsPerIter.toStringAsFixed(6),
    ].join(',');
  }
}

class BenchmarkRunResult {
  final File csvFile;
  final int sizeCount;
  final int rowCount;

  const BenchmarkRunResult({
    required this.csvFile,
    required this.sizeCount,
    required this.rowCount,
  });
}

class FftBenchmarkRunner {
  static const int minExp = 5;
  static const int maxExp = 15;
  static const int defaultTargetSizeCount = 100;

  Future<Directory> reportsDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final reportsDir = Directory(
      '${docsDir.path}${Platform.pathSeparator}fft_bench_reports',
    );
    if (!await reportsDir.exists()) {
      await reportsDir.create(recursive: true);
    }
    return reportsDir;
  }

  Future<List<File>> listReports() async {
    final dir = await reportsDirectory();
    final files =
        (await dir
                .list()
                .where(
                  (entity) =>
                      entity is File &&
                      entity.path.toLowerCase().endsWith('.csv'),
                )
                .cast<File>()
                .toList())
            .toList();

    final withStats = <({File file, DateTime modified})>[];
    for (final file in files) {
      final modified = await file.lastModified();
      withStats.add((file: file, modified: modified));
    }

    withStats.sort((a, b) => b.modified.compareTo(a.modified));
    return withStats.map((entry) => entry.file).toList(growable: false);
  }

  Future<BenchmarkRunResult> runAndSave({
    int targetSizeCount = defaultTargetSizeCount,
    BenchmarkProgress? onProgress,
  }) async {
    onProgress?.call('Starting benchmark isolate...');
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(_benchmarkIsolateMain, <String, Object>{
      'send_port': receivePort.sendPort,
      'target_size_count': targetSizeCount,
    });

    Map<String, Object>? payload;
    await for (final message in receivePort) {
      if (message is! Map) {
        continue;
      }
      final type = message['type'];
      if (type == 'progress') {
        final current = message['current'] as int?;
        final total = message['total'] as int?;
        final nfft = message['nfft'] as int?;
        if (current != null && total != null && nfft != null) {
          onProgress?.call('Benchmarking nfft=$nfft ($current/$total)');
        }
      } else if (type == 'done') {
        payload = message.cast<String, Object>();
        receivePort.close();
        break;
      } else if (type == 'error') {
        receivePort.close();
        isolate.kill(priority: Isolate.immediate);
        final error = message['error'] ?? 'Unknown isolate error';
        throw StateError('Benchmark isolate failed: $error');
      }
    }
    isolate.kill(priority: Isolate.immediate);

    if (payload == null) {
      throw StateError('Benchmark isolate ended without a result');
    }

    final dir = await reportsDirectory();
    final now = DateTime.now();
    final fileName = 'fft_bench_${_timestamp(now)}.csv';
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(payload['csv']! as String);

    onProgress?.call('Saved report: ${file.path}');

    return BenchmarkRunResult(
      csvFile: file,
      sizeCount: payload['size_count']! as int,
      rowCount: payload['row_count']! as int,
    );
  }

  String _timestamp(DateTime dt) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dt.year}${two(dt.month)}${two(dt.day)}_${two(dt.hour)}${two(dt.minute)}${two(dt.second)}';
  }
}

void _benchmarkIsolateMain(Map<String, Object> args) {
  final sendPort = args['send_port'] as SendPort;
  final targetSizeCount = args['target_size_count'] as int;

  try {
    final payload = _runBenchmarkPayloadWithProgress(targetSizeCount, (
      current,
      total,
      nfft,
    ) {
      sendPort.send(<String, Object>{
        'type': 'progress',
        'current': current,
        'total': total,
        'nfft': nfft,
      });
    });
    sendPort.send(payload);
  } catch (e) {
    sendPort.send(<String, Object>{'type': 'error', 'error': e.toString()});
  }
}

Map<String, Object> _runBenchmarkPayloadWithProgress(
  int targetSizeCount,
  void Function(int current, int total, int nfft) onProgress,
) {
  final sizes = generateBenchmarkSizes(
    minExp: FftBenchmarkRunner.minExp,
    maxExp: FftBenchmarkRunner.maxExp,
    targetCount: targetSizeCount,
  );

  final rows = <BenchRow>[];
  for (var i = 0; i < sizes.length; i++) {
    final nfft = sizes[i];
    onProgress(i + 1, sizes.length, nfft);
    rows.addAll(runBenchmarksForNfft(nfft));
  }

  final csv = buildCsv(rows);
  return <String, Object>{
    'type': 'done',
    'csv': csv,
    'size_count': sizes.length,
    'row_count': rows.length,
  };
}

double benchmark(BenchFn fn, {required int warmup, required int iterations}) {
  double sink = 0.0;

  for (var i = 0; i < warmup; i++) {
    sink += fn();
  }

  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    sink += fn();
  }
  sw.stop();

  if (!sink.isFinite) {
    throw StateError('Benchmark sink became non-finite');
  }

  return sw.elapsedMicroseconds / iterations;
}

int defaultIterationsForNfft(int nfft) {
  if (nfft <= 1 << 8) return 4000;
  if (nfft <= 1 << 10) return 2000;
  if (nfft <= 1 << 12) return 1000;
  if (nfft <= 1 << 14) return 300;
  return 100;
}

List<int> generateBenchmarkSizes({
  required int minExp,
  required int maxExp,
  required int targetCount,
}) {
  if (minExp > maxExp) {
    throw ArgumentError('minExp must be <= maxExp');
  }
  if (targetCount <= 0) {
    throw ArgumentError('targetCount must be > 0');
  }

  final minSize = 1 << minExp;
  final maxSize = 1 << maxExp;

  // Always include all 5-smooth sizes: 2^a * 3^b * 5^c in range.
  final out = _generate235SmoothInRange(minSize: minSize, maxSize: maxSize);

  // targetCount is treated as a minimum.
  if (out.length >= targetCount) {
    return out.toList()..sort();
  }

  final extrasNeeded = targetCount - out.length;
  if (extrasNeeded == 1) {
    out.add(minSize);
  } else {
    for (var i = 0; i < extrasNeeded; i++) {
      final t = i / (extrasNeeded - 1);
      final v = minSize * math.pow(maxSize / minSize, t);
      out.add(v.round().clamp(minSize, maxSize));
    }
  }

  return out.toList()..sort();
}

Set<int> _generate235SmoothInRange({
  required int minSize,
  required int maxSize,
}) {
  final out = <int>{};
  for (var p2 = 1; p2 <= maxSize; p2 *= 2) {
    for (var p3 = 1; p2 * p3 <= maxSize; p3 *= 3) {
      for (var v = p2 * p3; v <= maxSize; v *= 5) {
        if (v >= minSize) {
          out.add(v);
        }
      }
    }
  }
  return out;
}

Float32List sineF32(int nfft) {
  return SignalGenerator.sine(n: nfft, freqHz: 440.0, sampleRate: 16000.0);
}

List<double> sineF64List(Float32List x) {
  return x.map((v) => v.toDouble()).toList(growable: false);
}

List<BenchRow> runBenchmarksForNfft(int nfft) {
  final rows = <BenchRow>[];
  final warmup = 200;
  final iterations = defaultIterationsForNfft(nfft);

  final realInput = sineF32(nfft);
  final realInputFftea = sineF64List(realInput);
  final imagInput = Float32List(nfft);
  for (var i = 0; i < nfft; i++) {
    imagInput[i] = 0.5 * realInput[i];
  }

  late final RfftPlan rfftPlan;
  late final CfftPlan cfftPlan;
  try {
    rfftPlan = RfftPlan(nfft);
    cfftPlan = CfftPlan(nfft);
  } catch (e) {
    developer.log('Skipping nfft=$nfft: plan creation failed ($e)');
    return rows;
  }
  fftea.FFT? ffteaFft;
  try {
    ffteaFft = fftea.FFT(nfft);
  } catch (_) {
    ffteaFft = null;
  }

  try {
    rows.add(
      BenchRow(
        libraryName: 'open_dspc',
        functionName: 'FFTStatic.rfft',
        nfft: nfft,
        warmup: warmup,
        iterations: iterations,
        microsecondsPerIter: benchmark(
          () => FFTStatic.rfft(realInput, n: nfft).realAt(0),
          warmup: warmup,
          iterations: iterations,
        ),
      ),
    );

    rows.add(
      BenchRow(
        libraryName: 'open_dspc',
        functionName: 'FFTStatic.rfftMag',
        nfft: nfft,
        warmup: warmup,
        iterations: iterations,
        microsecondsPerIter: benchmark(
          () => FFTStatic.rfftMag(realInput, n: nfft, mode: SpecMode.mag)[0],
          warmup: warmup,
          iterations: iterations,
        ),
      ),
    );

    rows.add(
      BenchRow(
        libraryName: 'open_dspc',
        functionName: 'RfftPlan.execute',
        nfft: nfft,
        warmup: warmup,
        iterations: iterations,
        microsecondsPerIter: benchmark(
          () => rfftPlan.execute(realInput).realAt(0),
          warmup: warmup,
          iterations: iterations,
        ),
      ),
    );

    rows.add(
      BenchRow(
        libraryName: 'open_dspc',
        functionName: 'RfftPlan.executeSpec',
        nfft: nfft,
        warmup: warmup,
        iterations: iterations,
        microsecondsPerIter: benchmark(
          () => rfftPlan.executeSpec(realInput, mode: SpecMode.mag)[0],
          warmup: warmup,
          iterations: iterations,
        ),
      ),
    );

    rows.add(
      BenchRow(
        libraryName: 'open_dspc',
        functionName: 'FFTStatic.fft',
        nfft: nfft,
        warmup: warmup,
        iterations: iterations,
        microsecondsPerIter: benchmark(
          () => FFTStatic.fft(realInput, imagInput, n: nfft).realAt(0),
          warmup: warmup,
          iterations: iterations,
        ),
      ),
    );

    rows.add(
      BenchRow(
        libraryName: 'open_dspc',
        functionName: 'CfftPlan.fft',
        nfft: nfft,
        warmup: warmup,
        iterations: iterations,
        microsecondsPerIter: benchmark(
          () => cfftPlan.fft(realInput, imagInput).realAt(0),
          warmup: warmup,
          iterations: iterations,
        ),
      ),
    );

    if (ffteaFft != null) {
      rows.add(
        BenchRow(
          libraryName: 'fftea',
          functionName: 'fftea.realFft',
          nfft: nfft,
          warmup: warmup,
          iterations: iterations,
          microsecondsPerIter: benchmark(
            () => ffteaFft!.realFft(realInputFftea)[0].x,
            warmup: warmup,
            iterations: iterations,
          ),
        ),
      );
    }
  } finally {
    rfftPlan.close();
    cfftPlan.close();
  }

  return rows;
}

Future<void> writeCsv(String path, List<BenchRow> rows) async {
  await File(path).writeAsString(buildCsv(rows));
}

String buildCsv(List<BenchRow> rows) {
  final buffer = StringBuffer()
    ..writeln('library,function,nfft,warmup,iterations,microseconds_per_iter');
  for (final row in rows) {
    buffer.writeln(row.toCsv());
  }
  return buffer.toString();
}
