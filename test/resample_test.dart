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
    print(x.sublist(0, 10));
    print(r.sublist(0, 10));
  });
  test('resampler value', () {
    const n = 16000 * 8;
    final x = SignalGenerator.sine(n: n, freqHz: 440.0, sampleRate: 16000.0);
    final res = Resampler(origFreq: 16000, newFreq: 8000);
    final r = res.process(x);
    print(x.sublist(0, 10));
    print(r.sublist(0, 10));
    res.close();
  });
}
