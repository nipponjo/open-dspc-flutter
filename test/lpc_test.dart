import 'package:test/test.dart';
import 'package:open_dspc/open_dspc.dart';

void main() {
  test('LPC test: ', () {
    const n = 128;
    final x = SignalGenerator.sawtooth(
      n: n,
      freqHz: 440.0,
      sampleRate: 16000.0,
    );

    final lpcCoeffs = Lpc.lpc(x, order: 5);
    final lpcCoeffsBurg = Lpc.lpc(x, order: 5, method: LpcMethod.burg);

    expect(lpcCoeffs.length, 6);
    expect(lpcCoeffsBurg.length, 6);
    expect(lpcCoeffsBurg[0], 1.0);
  });
}
