import 'package:test/test.dart';

import 'package:open_dspc/open_dspc.dart';

void main() {
  test('resample value', () {
    const n = 16000 * 8;
    final x = SignalGenerator.sine(n: n, freqHz: 440.0, sampleRate: 16000.0);
    final r = Resample.process(
      x,
      origFreq: 16000,
      newFreq: 8000,
      method: ResamplingMethod.sincHann,
    );
    expect(r.length, n ~/ 2);
  });
  test('resampler value', () {
    const n = 16000 * 8;
    final x = SignalGenerator.sine(n: n, freqHz: 440.0, sampleRate: 16000.0);
    final res = Resampler(origFreq: 16000, newFreq: 8000);
    final r = res.process(x);
    expect(r.length, res.outLenFor(x.length));
    res.close();
  });
}
