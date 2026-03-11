import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:open_dspc/open_dspc.dart';
import 'test_helpers.dart';

void main() {
  test('Conv values test', () {
    final x = Float32List.fromList([1, 1, 1, 1, 1]);
    final y = Float32List.fromList([1, 1, 1, 1, 1]);

    final xyFull = Conv.direct(x, y, outMode: CorrOutMode.full, simd: true);
    final xySame = Conv.direct(x, y, outMode: CorrOutMode.same);
    final xyValid = Conv.direct(x, y, outMode: CorrOutMode.valid);

    print("Full: $xyFull");
    print("Same: $xySame");
    print("Valid: $xyValid");
  });

  test('Conv test: direct and FFT agree', () {
    const n = 16;

    final x = SignalGenerator.sine(n: n, freqHz: 440.0, sampleRate: 16000.0);
    final y = SignalGenerator.sine(n: n, freqHz: 400.0, sampleRate: 16000.0);

    final fftconv = FftConvolver(xMax: n, hMax: n);
    final xyConv = Conv.direct(x, y, mode: ConvMode.xcorr);
    final xyFftConv = fftconv.process(x, y, mode: ConvMode.xcorr);

    print(xyConv);
    print(xyFftConv);
    expect(xyConv, closeToList(xyFftConv, 1e-6));
    fftconv.close();
  });

  test('Conv direct: SIMD and scalar agree (full/valid/same)', () {
    const n = 257;
    final x = SignalGenerator.sine(n: n, freqHz: 440.0, sampleRate: 16000.0);
    final h = SignalGenerator.sine(n: 63, freqHz: 1200.0, sampleRate: 16000.0);

    for (final outMode in CorrOutMode.values) {
      final yScalar = Conv.direct(
        x,
        h,
        mode: ConvMode.convolution,
        outMode: outMode,
        simd: false,
      );
      final ySimd = Conv.direct(
        x,
        h,
        mode: ConvMode.convolution,
        outMode: outMode,
        simd: true,
      );
      expect(ySimd, closeToList(yScalar, 1e-3));
    }
  });

  test('Conv direct benchmark: SIMD vs scalar runtime', () {
    final x = SignalGenerator.sine(n: 1024, freqHz: 440.0, sampleRate: 16000.0);
    final h = SignalGenerator.sine(n: 257, freqHz: 700.0, sampleRate: 16000.0);
    const iters = 80;

    for (var i = 0; i < 10; i++) {
      Conv.direct(x, h, outMode: CorrOutMode.full, simd: false);
      Conv.direct(x, h, outMode: CorrOutMode.full, simd: true);
    }

    final swScalar = Stopwatch()..start();
    for (var i = 0; i < iters; i++) {
      Conv.direct(x, h, outMode: CorrOutMode.full, simd: false);
    }
    swScalar.stop();

    final swSimd = Stopwatch()..start();
    for (var i = 0; i < iters; i++) {
      Conv.direct(x, h, outMode: CorrOutMode.full, simd: true);
    }
    swSimd.stop();

    final scalarUs = swScalar.elapsedMicroseconds / iters;
    final simdUs = swSimd.elapsedMicroseconds / iters;
    print(
      'conv_direct(full, nx=${x.length}, nh=${h.length}, iters=$iters): '
      'scalar=${scalarUs.toStringAsFixed(1)} us, '
      'simd=${simdUs.toStringAsFixed(1)} us, '
      'speedup=${(scalarUs / simdUs).toStringAsFixed(3)}x',
    );
  });

  test('correlationLags matches scipy conventions', () {
    expect(
      Conv.correlationLags(4, 3, mode: CorrOutMode.full),
      Int32List.fromList([-2, -1, 0, 1, 2, 3]),
    );
    expect(
      Conv.correlationLags(4, 3, mode: CorrOutMode.same),
      Int32List.fromList([-1, 0, 1, 2]),
    );
    expect(
      Conv.correlationLags(4, 3, mode: CorrOutMode.valid),
      Int32List.fromList([0, 1]),
    );
    expect(
      Conv.correlationLags(3, 5, mode: CorrOutMode.valid),
      Int32List.fromList([-2, -1, 0]),
    );
  });
}
