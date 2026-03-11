import 'dart:math' as math;
import 'dart:typed_data';

/// Supported scalar window functions for frame-based DSP operations.
enum WindowType { rect, hann, hamming, blackman }

/// Returns a window of [length] for the selected [type].
///
/// By default this uses the periodic form, which is typically what you want
/// for FFT/STFT analysis. Set [periodic] to `false` to generate the symmetric
/// form instead.
Float32List generateWindow(
  int length, {
  WindowType type = WindowType.hann,
  bool periodic = true,
}) {
  _checkWindowLength(length);

  final window = Float32List(length);
  if (length == 1) {
    window[0] = 1.0;
    return window;
  }

  if (type == WindowType.rect) {
    for (var i = 0; i < length; i++) {
      window[i] = 1.0;
    }
    return window;
  }

  final denom = periodic ? length : length - 1;
  final phaseScale = (2.0 * math.pi) / denom;

  for (var n = 0; n < length; n++) {
    final phase = phaseScale * n;
    switch (type) {
      case WindowType.rect:
        window[n] = 1.0;
      case WindowType.hann:
        window[n] = 0.5 - 0.5 * math.cos(phase);
      case WindowType.hamming:
        window[n] = 0.54 - 0.46 * math.cos(phase);
      case WindowType.blackman:
        window[n] = 0.42 - 0.5 * math.cos(phase) + 0.08 * math.cos(2.0 * phase);
    }
  }

  return window;
}

Float32List rectWindow(int length, {bool periodic = true}) =>
    generateWindow(length, type: WindowType.rect, periodic: periodic);

Float32List hannWindow(int length, {bool periodic = true}) =>
    generateWindow(length, type: WindowType.hann, periodic: periodic);

Float32List hammingWindow(int length, {bool periodic = true}) =>
    generateWindow(length, type: WindowType.hamming, periodic: periodic);

Float32List blackmanWindow(int length, {bool periodic = true}) =>
    generateWindow(length, type: WindowType.blackman, periodic: periodic);

/// Returns a new array containing `input[n] * window[n]`.
Float32List multiplyWithWindow(Float32List input, Float32List window) {
  _checkSameLength(input, window);
  final output = Float32List(input.length);
  for (var i = 0; i < input.length; i++) {
    output[i] = input[i] * window[i];
  }
  return output;
}

/// Multiplies [input] by [window] in place.
void multiplyWithWindowInPlace(Float32List input, Float32List window) {
  _checkSameLength(input, window);
  for (var i = 0; i < input.length; i++) {
    input[i] *= window[i];
  }
}

/// Returns a new array containing [input] multiplied by a generated window.
Float32List applyWindow(
  Float32List input, {
  WindowType type = WindowType.hann,
  bool periodic = true,
}) {
  return multiplyWithWindow(
    input,
    generateWindow(input.length, type: type, periodic: periodic),
  );
}

/// Multiplies [input] in place by a generated window.
void applyWindowInPlace(
  Float32List input, {
  WindowType type = WindowType.hann,
  bool periodic = true,
}) {
  multiplyWithWindowInPlace(
    input,
    generateWindow(input.length, type: type, periodic: periodic),
  );
}

void _checkWindowLength(int length) {
  if (length <= 0) {
    throw ArgumentError.value(length, 'length', 'must be > 0');
  }
}

void _checkSameLength(Float32List input, Float32List window) {
  if (input.length != window.length) {
    throw ArgumentError(
      'input and window must have the same length: '
      '${input.length} != ${window.length}',
    );
  }
}
