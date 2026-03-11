import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:open_dspc/open_dspc.dart';

void main() {
  test('FFt test: cpx -> abs', () {
    const n = 64;
    final fft = RfftPlan(n);

    final y = SignalGenerator.linspace(0, 1, num: n);
    final cpx = fft.execute(y);
    print(y);
    print(cpx.real);
    print(cpx.imag);
    fft.close();
  });
  test('FFt values', () {
    final x = Float32List.fromList([1, 2, 3, 4, 5]);
    final n = x.length;
    final fft = RfftPlan(n);

    final cpx = fft.execute(x);
    print(cpx.real);
    print(cpx.imag);
    fft.close();
  });
  test('Mel test', () {
    const n = 1024;

    final x = SignalGenerator.sine(n: n, freqHz: 440.0, sampleRate: 16000.0);

    final melBins = frameToMel(
      x,
      sr: 16000,
      scale: MelScale.slaney,
      norm: MelNorm.none,
    );

    print(melBins);
  });
  test('rfftMag test', () {
    const n = 1024;

    final x = SignalGenerator.sine(n: n, freqHz: 440.0, sampleRate: 16000.0);

    final melBins = FFTStatic.rfftMag(x, mode: SpecMode.power);
    print(melBins);
  });
  test('fft-ifft round test', () {
    const n = 1024;

    final x = SignalGenerator.sine(n: n, freqHz: 440.0, sampleRate: 16000.0);
    final y = SignalGenerator.cosine(n: n, freqHz: 440.0, sampleRate: 16000.0);

    final xyFft = FFTStatic.fft(x, y);
    final xyRec = FFTStatic.ifft(xyFft.real, xyFft.imag);

    print(x.sublist(0, 10));
    print(xyRec.real.sublist(0, 10));
    print(y.sublist(0, 10));
    print(xyRec.imag.sublist(0, 10));
  });
  test('rfft-irfft round test', () {
    const n = 1024;

    final x = SignalGenerator.sine(n: n, freqHz: 440.0, sampleRate: 16000.0);

    final Complex32List xFft = FFTStatic.rfft(x, n: 2 * n);
    final xRec = FFTStatic.irfft(xFft.real, xFft.imag, n: 2 * n);

    print(x.sublist(0, 10));
    print(xRec.sublist(0, 10));
  });
}
