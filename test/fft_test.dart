import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:open_dspc/open_dspc.dart';

void main() {
  test('FFt test: cpx -> abs', () {
    const n = 64;
    final fft = RfftPlan(n);

    final y = SignalGenerator.linspace(0, 1, num: n);
    final cpx = fft.execute(y);
    expect(cpx.real.length, n ~/ 2 + 1);
    expect(cpx.imag.length, n ~/ 2 + 1);
    fft.close();
  });
  test('FFt values', () {
    final x = Float32List.fromList([1, 2, 3, 4, 5]);
    final n = x.length;
    final fft = RfftPlan(n);

    final cpx = fft.execute(x);
    expect(cpx.real.length, n ~/ 2 + 1);
    expect(cpx.imag.length, n ~/ 2 + 1);
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

    expect(melBins, isNotEmpty);
  });
  test('rfftMag test', () {
    const n = 1024;

    final x = SignalGenerator.sine(n: n, freqHz: 440.0, sampleRate: 16000.0);

    final melBins = FFTStatic.rfftMag(x, mode: SpecMode.power);
    expect(melBins, isNotEmpty);
  });
  test('fft-ifft round test', () {
    const n = 1024;

    final x = SignalGenerator.sine(n: n, freqHz: 440.0, sampleRate: 16000.0);
    final y = SignalGenerator.cosine(n: n, freqHz: 440.0, sampleRate: 16000.0);

    final xyFft = FFTStatic.fft(x, y);
    final xyRec = FFTStatic.ifft(xyFft.real, xyFft.imag);

    expect(xyRec.real.length, n);
    expect(xyRec.imag.length, n);
  });
  test('rfft-irfft round test', () {
    const n = 1024;

    final x = SignalGenerator.sine(n: n, freqHz: 440.0, sampleRate: 16000.0);

    final Complex32List xFft = FFTStatic.rfft(x, n: 2 * n);
    final xRec = FFTStatic.irfft(xFft.real, xFft.imag, n: 2 * n);

    expect(xRec.length, 2 * n);
  });
}
