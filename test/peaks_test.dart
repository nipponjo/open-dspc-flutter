import 'dart:typed_data';

import 'package:open_dspc/open_dspc.dart';
import 'package:test/test.dart';
import 'test_helpers.dart';

void main() {
  test('find_peaks basic usage with height and distance', () {
    final x = Float32List.fromList([0, 1, 0, 2, 0, 1, 0]);

    final result = find_peaks(x, height: 0.5, distance: 2);

    expect(result.peaks, Int64List.fromList([1, 3, 5]));
    expect(result.properties.peak_heights, isNotNull);
    expect(result.properties.peak_heights!, closeToList([1, 2, 1], 1e-6));
  });

  test('find_peaks supports interval-style prominence and width filters', () {
    final x = Float32List.fromList([0, 3, 0, 1, 0, 2, 2, 2, 0]);

    final result = find_peaks(
      x,
      prominence: (1.5, null),
      width: [1, 4],
      plateau_size: (1, null),
    );

    expect(result.peaks, Int64List.fromList([1, 6]));
    expect(result.properties.prominences, isNotNull);
    expect(result.properties.widths, isNotNull);
    expect(result.properties.plateau_sizes, Int64List.fromList([1, 3]));
  });

  test('find_peaks accepts array-backed height constraints', () {
    final x = Float32List.fromList([0, 1, 0, 2, 0, 1, 0]);
    final minHeight = Float32List.fromList([0, 1.5, 0, 1.5, 0, 1.5, 0]);

    final result = find_peaks(x, height: minHeight);

    expect(result.peaks, Int64List.fromList([3]));
    expect(result.properties.peak_heights, closeToList([2], 1e-6));
  });

  test('find_peaks returns threshold properties when requested', () {
    final x = Float32List.fromList([0, 2, 1, 3, 1, 0]);

    final result = find_peaks(x, threshold: 1.5);

    expect(result.peaks, Int64List.fromList([3]));
    expect(result.properties.left_thresholds, closeToList([2], 1e-6));
    expect(result.properties.right_thresholds, closeToList([2], 1e-6));
  });

  test('find_peaks values for a sine fn', () {
    final x = SignalGenerator.sine(n: 100, freqHz: 2 * 440, sampleRate: 16000);

    final result = find_peaks(x, prominence: 0.8);
    print(result.peaks);
  });
}
