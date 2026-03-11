import 'dart:math' as math;
import 'dart:typed_data';

class SignalGenerator64 {
  const SignalGenerator64._(); // static-only utility

  // =============================
  // Sine wave
  // =============================
  static Float64List sine({
    required int n,
    required double freqHz,
    required double sampleRate,
    double amplitude = 1.0,
    double phaseRad = 0.0,
  }) {
    final out = Float64List(n);
    final w = 2.0 * math.pi * freqHz / sampleRate;

    for (int i = 0; i < n; i++) {
      out[i] = (amplitude * math.sin(w * i + phaseRad));
    }
    return out;
  }

  // =============================
  // Cosine wave
  // =============================
  static Float64List cosine({
    required int n,
    required double freqHz,
    required double sampleRate,
    double amplitude = 1.0,
    double phaseRad = 0.0,
  }) {
    final out = Float64List(n);
    final w = 2.0 * math.pi * freqHz / sampleRate;

    for (int i = 0; i < n; i++) {
      out[i] = (amplitude * math.cos(w * i + phaseRad));
    }
    return out;
  }

  // =============================
  // White noise (dart:math Random)
  // =============================
  static Float64List whiteNoise(int n, {double amplitude = 1.0, int? seed}) {
    final rng = math.Random(seed);
    final out = Float64List(n);

    for (int i = 0; i < n; i++) {
      out[i] = (amplitude * (2.0 * rng.nextDouble() - 1.0));
    }
    return out;
  }

  // =============================
  // LCG noise (deterministic)
  // =============================
  static Float64List lcgNoise(
    int n, {
    double amplitude = 1.0,
    int seed = 123456789,
  }) {
    int x = seed & 0x7fffffff;
    const int a = 1103515245;
    const int c = 12345;
    const int m = 0x7fffffff;

    double next() {
      x = (a * x + c) & m;
      return x / m;
    }

    final out = Float64List(n);
    for (int i = 0; i < n; i++) {
      out[i] = (amplitude * (2.0 * next() - 1.0));
    }
    return out;
  }

  // =============================
  // Pulse train
  // =============================
  static Float64List pulseTrain({
    required int n,
    required double freqHz,
    required double sampleRate,
    double amplitude = 1.0,
    double dutyCycle = 0.5, // 0..1
  }) {
    final out = Float64List(n);
    final period = sampleRate / freqHz;

    for (int i = 0; i < n; i++) {
      final phase = (i % period) / period;
      out[i] = phase < dutyCycle ? amplitude : 0.0;
    }
    return out;
  }

  // =============================
  // Sawtooth
  // =============================
  static Float64List sawtooth({
    required int n,
    required double freqHz,
    required double sampleRate,
    double amplitude = 1.0,
  }) {
    final out = Float64List(n);
    final period = sampleRate / freqHz;

    for (int i = 0; i < n; i++) {
      final phase = (i % period) / period;
      out[i] = (amplitude * (2.0 * phase - 1.0));
    }
    return out;
  }

  // =============================
  // Linear frequency sweep (chirp)
  // =============================
  static Float64List linearSweep({
    required int n,
    required double fStart,
    required double fEnd,
    required double sampleRate,
    double amplitude = 1.0,
  }) {
    final out = Float64List(n);
    final T = n / sampleRate;
    final k = (fEnd - fStart) / T;

    for (int i = 0; i < n; i++) {
      final t = i / sampleRate;
      final phase = 2.0 * math.pi * (fStart * t + 0.5 * k * t * t);
      out[i] = (amplitude * math.sin(phase));
    }
    return out;
  }

  // =============================
  // Exponential (log) sweep
  // =============================
  static Float64List exponentialSweep({
    required int n,
    required double fStart,
    required double fEnd,
    required double sampleRate,
    double amplitude = 1.0,
  }) {
    final out = Float64List(n);
    final T = n / sampleRate;

    final K = T * fStart / math.log(fEnd / fStart);
    final L = math.log(fEnd / fStart);

    for (int i = 0; i < n; i++) {
      final t = i / sampleRate;
      final phase = 2.0 * math.pi * K * (math.exp(t * L / T) - 1.0);
      out[i] = (amplitude * math.sin(phase));
    }
    return out;
  }

  // =============================
  // like np.arange(startOrStop, stop?, step?)
  // =============================
  static Float64List arange(num startOrStop, [num? stop, num step = 1]) {
    final start = stop == null ? 0 : startOrStop;
    final end = stop ?? startOrStop;
    final length = ((end - start) / step).ceil();
    final out = Float64List(length);

    for (int i = 0; i < length; i++) {
      out[i] = (start + i * step).toDouble();
    }
    return out;
  }

  // =============================
  /// Generates a sequence of evenly spaced values over a specified interval.
  ///
  /// Similar to NumPy's linspace. Returns [num] samples from [start] to [stop].
  /// If [endpoint] is true (default), [stop] is included as the last value.
  /// If [endpoint] is false, [stop] is excluded.
  static Float64List linspace(
    double start,
    double stop, {
    int num = 50,
    bool endpoint = true,
  }) {
    if (num < 2) {
      return Float64List.fromList([start]);
    }
    final out = Float64List(num);
    final step = endpoint ? (stop - start) / (num - 1) : (stop - start) / num;
    for (int i = 0; i < num; i++) {
      out[i] = start + step * i;
    }
    return out;
  }
}
