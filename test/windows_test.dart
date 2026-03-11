import 'dart:typed_data';

import 'package:open_dspc/open_dspc.dart';
import 'package:test/test.dart';

void main() {
  test('hann window uses periodic form by default', () {
    final window = hannWindow(4);

    expect(window.length, 4);
    expect(window[0], closeTo(0.0, 1e-6));
    expect(window[1], closeTo(0.5, 1e-6));
    expect(window[2], closeTo(1.0, 1e-6));
    expect(window[3], closeTo(0.5, 1e-6));
  });

  test('named windows match generic generator', () {
    expect(
      hammingWindow(8),
      orderedEquals(generateWindow(8, type: WindowType.hamming)),
    );
    expect(
      blackmanWindow(8),
      orderedEquals(generateWindow(8, type: WindowType.blackman)),
    );
    expect(
      rectWindow(8),
      orderedEquals(generateWindow(8, type: WindowType.rect)),
    );
  });

  test('multiplyWithWindow returns a new array', () {
    final input = Float32List.fromList([1, 2, 3, 4]);
    final window = Float32List.fromList([1, 0.5, 0.25, 0]);

    final output = multiplyWithWindow(input, window);

    expect(output, orderedEquals([1, 1, 0.75, 0]));
    expect(input, orderedEquals([1, 2, 3, 4]));
  });

  test('multiplyWithWindowInPlace mutates the input', () {
    final input = Float32List.fromList([1, 2, 3, 4]);
    final window = Float32List.fromList([1, 0.5, 0.25, 0]);

    multiplyWithWindowInPlace(input, window);

    expect(input, orderedEquals([1, 1, 0.75, 0]));
  });

  test('applyWindow and applyWindowInPlace agree', () {
    final input = Float32List.fromList([1, 2, 3, 4, 5, 6]);
    final copy = Float32List.fromList(input);

    final out = applyWindow(input, type: WindowType.blackman);
    applyWindowInPlace(copy, type: WindowType.blackman);

    expect(copy, orderedEquals(out));
    expect(input, orderedEquals([1, 2, 3, 4, 5, 6]));
  });

  test('window multiplication validates input sizes', () {
    final input = Float32List(4);
    final window = Float32List(3);

    expect(() => multiplyWithWindow(input, window), throwsArgumentError);
    expect(() => multiplyWithWindowInPlace(input, window), throwsArgumentError);
  });
}
