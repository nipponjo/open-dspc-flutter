import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:open_dspc/open_dspc.dart';

void main() {
  test('polyfit value', () {
    const n = 1024;
    final x = SignalGenerator64.sine(n: n, freqHz: 440.0, sampleRate: 16000.0);
    final y = SignalGenerator64.cosine(
      n: n,
      freqHz: 440.0,
      sampleRate: 16000.0,
    );
    const nIter = 200;

    final sw = Stopwatch()..start();
    Float64List? r;
    Float64List? yhat;

    for (var i = 0; i < nIter; i++) {
      final pf = Polyfitter(deg: 8);
      r = pf.polyfit(
        // Float64List.fromList([1, 2, 3, 4, 5, 6, 7]),
        // Float64List.fromList([1, 2, 3, 4, 5, 6, 7]),
        x,
        y,
      );
      // sink += r[0];
      yhat = pf.polyval(x);
    }

    sw.stop();

    final usPerIter = sw.elapsedMicroseconds / nIter;
    print(r);
    print(y.sublist(0, 10));
    print(yhat!.sublist(0, 10));

    print('lfilter: ${usPerIter.toStringAsFixed(2)} µs/iter (n=$n)');
  });
}
