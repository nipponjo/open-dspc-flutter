import 'dart:math' as math;
import 'dart:typed_data';

import 'package:open_dspc/open_dspc.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

Float32List _makeSignal(int n) {
  final rnd = math.Random(1337);
  final x = Float32List(n);
  for (var i = 0; i < n; i++) {
    final t = i / n;
    final tone =
        math.sin(2 * math.pi * 7.0 * t) +
        0.35 * math.sin(2 * math.pi * 17.0 * t);
    final noise = (rnd.nextDouble() - 0.5) * 0.02;
    x[i] = (tone + noise).toDouble();
  }
  return x;
}

void main() {
  test('Xcorr direct: SIMD and scalar agree (full/valid/same)', () {
    final x = _makeSignal(513);
    const modes = [CorrOutMode.full, CorrOutMode.valid, CorrOutMode.same];

    for (final mode in modes) {
      final yScalar = Conv.autocorrDirect(x, mode: mode, simd: false);
      final ySimd = Conv.autocorrDirect(x, mode: mode, simd: true);
      expect(ySimd.length, yScalar.length);
      expect(ySimd, closeToList(yScalar, 1e-3));
    }
  });

  test('Xcorr direct benchmark: SIMD vs scalar runtime', () {
    final x = _makeSignal(1024);
    const iters = 80;

    for (var i = 0; i < 10; i++) {
      Conv.autocorrDirect(x, mode: CorrOutMode.full, simd: false);
      Conv.autocorrDirect(x, mode: CorrOutMode.full, simd: true);
    }

    final swScalar = Stopwatch()..start();
    for (var i = 0; i < iters; i++) {
      Conv.autocorrDirect(x, mode: CorrOutMode.full, simd: false);
    }
    swScalar.stop();

    final swSimd = Stopwatch()..start();
    for (var i = 0; i < iters; i++) {
      Conv.autocorrDirect(x, mode: CorrOutMode.full, simd: true);
    }
    swSimd.stop();

    final scalarUs = swScalar.elapsedMicroseconds / iters;
    final simdUs = swSimd.elapsedMicroseconds / iters;
    print(
      'autocorr_direct(full, n=${x.length}, iters=$iters): '
      'scalar=${scalarUs.toStringAsFixed(1)} us, '
      'simd=${simdUs.toStringAsFixed(1)} us, '
      'speedup=${(scalarUs / simdUs).toStringAsFixed(3)}x',
    );
  });
}
