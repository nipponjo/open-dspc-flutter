import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';

import 'package:fftea/fftea.dart' as fftea;
import 'package:open_dspc/open_dspc.dart';

typedef BenchFn = double Function();

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

  Map<String, Object> toJson() {
    return {
      'library': libraryName,
      'function': functionName,
      'nfft': nfft,
      'warmup': warmup,
      'iterations': iterations,
      'microseconds_per_iter': microsecondsPerIter,
    };
  }
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

  // Keep benchmarked work observable.
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
    stdout.writeln('Skipping nfft=$nfft: plan creation failed ($e)');
    return rows;
  }
  fftea.FFT? ffteaFft;
  try {
    ffteaFft = fftea.FFT(nfft);
  } catch (_) {
    // Some FFT libraries only support restricted lengths.
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
  final buffer = StringBuffer()
    ..writeln(
      'library,function,nfft,warmup,iterations,microseconds_per_iter',
    );
  for (final row in rows) {
    buffer.writeln(row.toCsv());
  }
  await File(path).writeAsString(buffer.toString());
}

Future<void> writeJsonMetadata(
  String path,
  List<BenchRow> rows, {
  required List<int> sizes,
}) async {
  final payload = {
    'generated_at_utc': DateTime.now().toUtc().toIso8601String(),
    'nfft_sizes': sizes,
    'rows': rows.map((row) => row.toJson()).toList(),
  };
  await File(path).writeAsString(
    const JsonEncoder.withIndent('  ').convert(payload),
  );
}

Future<void> main(List<String> args) async {
  final runId = 's100_m4_auto';
  final csvPath = args.isNotEmpty ? args[0] : 'fft_bench_results_$runId.csv';
  // final jsonPath = args.length > 1 ? args[1] : 'fft_bench_results.json';
  const minExp = 5;
  const maxExp = 15;
  const defaultTargetSizeCount = 100;
  final targetSizeCount = args.length > 1
      ? int.tryParse(args[1]) ?? defaultTargetSizeCount
      : defaultTargetSizeCount;
  final nfftSizes = generateBenchmarkSizes(
    minExp: minExp,
    maxExp: maxExp,
    targetCount: targetSizeCount,
  );

  stdout.writeln('Testing ${nfftSizes.length} FFT sizes: $nfftSizes');

  final rows = <BenchRow>[];
  for (final nfft in nfftSizes) {
    stdout.writeln('Benchmarking nfft=$nfft');
    final nfftRows = runBenchmarksForNfft(nfft);
    rows.addAll(nfftRows);

    for (final row in nfftRows) {
      stdout.writeln(
        '${row.libraryName}.${row.functionName} nfft=${row.nfft} '
        '${row.microsecondsPerIter.toStringAsFixed(3)} us/iter',
      );
    }
  }

  await writeCsv(csvPath, rows);
  // await writeJsonMetadata(jsonPath, rows, sizes: nfftSizes);

  stdout.writeln('Wrote CSV results to $csvPath');
  // stdout.writeln('Wrote JSON metadata to $jsonPath');
}
