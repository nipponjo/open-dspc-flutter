import 'dart:typed_data';

import 'package:open_dspc/open_dspc.dart';
import 'package:test/test.dart';

void main() {
  test('STFT process matches streaming push/flush', () {
    final signal = SignalGenerator.sine(
      n: 2500,
      freqHz: 440.0,
      sampleRate: 16000.0,
    );

    final offline = STFT.offline(nFft: 256, winLen: 256, hop: 64);
    final expected = offline.process(signal);

    final streaming = STFT.streaming(nFft: 256, winLen: 256, hop: 64);
    final batches = <STFTFrames>[
      streaming.push(Float32List.sublistView(signal, 0, 111)),
      streaming.push(Float32List.sublistView(signal, 111, 777)),
      streaming.push(Float32List.sublistView(signal, 777)),
      streaming.flush(),
    ];

    final actual = _concat(batches, streaming.bins);

    expect(actual.frames, expected.frames);
    expect(actual.bins, expected.bins);
    expect(actual.real.length, expected.real.length);
    expect(actual.imag.length, expected.imag.length);

    for (var i = 0; i < expected.real.length; i++) {
      expect(actual.real[i], closeTo(expected.real[i], 1e-4));
      expect(actual.imag[i], closeTo(expected.imag[i], 1e-4));
    }

    offline.close();
    streaming.close();
  });

  test('STFT processSpec power matches complex magnitude squared', () {
    final signal = SignalGenerator.sine(
      n: 2048,
      freqHz: 440.0,
      sampleRate: 16000.0,
    );

    final stft = STFT.offline(nFft: 256, winLen: 256, hop: 64);
    final complex = stft.process(signal);
    final power = stft.processSpec(signal, mode: SpecMode.power);

    expect(power.frames, complex.frames);
    expect(power.bins, complex.bins);

    for (var i = 0; i < power.values.length; i++) {
      final re = complex.real[i];
      final im = complex.imag[i];
      expect(power.values[i], closeTo((re * re) + (im * im), 5e-4));
    }

    stft.close();
  });
}

STFTFrames _concat(List<STFTFrames> batches, int bins) {
  final frames = batches.fold<int>(0, (sum, batch) => sum + batch.frames);
  final real = Float32List(frames * bins);
  final imag = Float32List(frames * bins);

  var offset = 0;
  for (final batch in batches) {
    final len = batch.frames * bins;
    real.setRange(offset, offset + len, batch.real);
    imag.setRange(offset, offset + len, batch.imag);
    offset += len;
  }

  return STFTFrames.fromBuffers(
    frames: frames,
    bins: bins,
    real: real,
    imag: imag,
  );
}
