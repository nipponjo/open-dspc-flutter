import 'dart:ffi' as ffi;
import 'dart:math' as math;
import 'dart:typed_data';

/// A complex-valued vector backed by separate real and imaginary arrays.
class Complex32List {
  final Float32List _real;
  final Float32List _imag;

  /// Creates a complex list of length [length] with zero-initialized storage.
  Complex32List(int length)
    : _real = Float32List(length),
      _imag = Float32List(length);

  /// Wraps existing real and imaginary arrays without copying.
  ///
  /// The two arrays must have identical length.
  Complex32List.wrap(Float32List real, Float32List imag)
    : assert(
        real.length == imag.length,
        'real and imag must have equal length',
      ),
      _real = real,
      _imag = imag;

  /// Creates a complex list from separate real and imaginary arrays.
  ///
  /// This performs a copy into newly allocated storage.
  factory Complex32List.fromRealImag(Float32List real, Float32List imag) {
    assert(real.length == imag.length, 'real and imag must have equal length');
    return Complex32List.wrap(
      Float32List.fromList(real),
      Float32List.fromList(imag),
    );
  }

  /// Creates a complex list by copying from real/imaginary FFI pointers.
  ///
  /// The caller must provide the number of complex elements in [length].
  factory Complex32List.fromRealImagPtr(
    ffi.Pointer<ffi.Float> realPtr,
    ffi.Pointer<ffi.Float> imagPtr,
    int length,
  ) {
    return Complex32List.wrap(
      Float32List.fromList(realPtr.asTypedList(length)),
      Float32List.fromList(imagPtr.asTypedList(length)),
    );
  }

  /// Number of complex elements.
  int get length => _real.length;

  /// Returns the real part at index [i].
  double realAt(int i) => _real[i];

  /// Returns the imaginary part at index [i].
  double imagAt(int i) => _imag[i];

  /// Sets the complex value at index [i].
  void set(int i, double re, double im) {
    _real[i] = re;
    _imag[i] = im;
  }

  Float32List get real => _real;
  Float32List get imag => _imag;

  /// Returns a copy of the real part.
  Float32List realCopy() => Float32List.fromList(_real);

  /// Returns a copy of the imaginary part.
  Float32List imagCopy() => Float32List.fromList(_imag);

  /// Returns a new [Complex32List] which is the complex conjugate of this list.
  Complex32List conj() {
    final outReal = Float32List.fromList(_real);
    final outImag = Float32List(length);
    for (int i = 0; i < length; i++) {
      outImag[i] = -_imag[i];
    }
    return Complex32List.wrap(outReal, outImag);
  }

  /// Returns the magnitude (absolute value) of each complex element.
  Float32List abs() {
    final out = Float32List(length);
    for (int i = 0; i < length; i++) {
      final re = _real[i];
      final im = _imag[i];
      out[i] = math.sqrt(re * re + im * im);
    }
    return out;
  }

  /// Returns the squared magnitude of each complex element.
  Float32List abs2() {
    final out = Float32List(length);
    for (int i = 0; i < length; i++) {
      final re = _real[i];
      final im = _imag[i];
      out[i] = re * re + im * im;
    }
    return out;
  }

  /// Returns the phase angle (argument) of each complex element.
  Float32List angle() {
    final out = Float32List(length);
    for (int i = 0; i < length; i++) {
      out[i] = math.atan2(_imag[i], _real[i]);
    }
    return out;
  }

  /// Multiplies all complex values by a real scalar [gain].
  void scale(double gain) {
    for (int i = 0; i < length; i++) {
      _real[i] *= gain;
      _imag[i] *= gain;
    }
  }

  /// In-place complex conjugation.
  void conjInPlace() {
    for (int i = 0; i < length; i++) {
      _imag[i] = -_imag[i];
    }
  }

  @override
  String toString() => 'Complex32List(length: $length)';
}

/// A complex-valued vector backed by `Float64x2` elements.
///
/// Each element stores `(real, imag)` in a single `Float64x2` slot.
class Complex64List {
  final Float64x2List _values;

  /// Creates a complex list of length [length] with zero-initialized storage.
  Complex64List(int length) : _values = Float64x2List(length);

  /// Wraps an existing `Float64x2List` without copying.
  ///
  /// The two components are stored as `(x, y)` pairs.
  const Complex64List.wrap(this._values);

  /// Creates a complex list from separate real and imaginary arrays.
  ///
  /// The two arrays must have identical length.
  factory Complex64List.fromRealImag(Float64List real, Float64List imag) {
    assert(real.length == imag.length, 'real and imag must have equal length');

    final values = Float64x2List(real.length);
    for (int i = 0; i < real.length; i++) {
      values[i] = Float64x2(real[i], imag[i]);
    }
    return Complex64List.wrap(values);
  }

  /// Creates a complex list from separate real and imaginary FFI buffers.
  ///
  /// The caller must provide the number of complex elements in [length].
  factory Complex64List.fromRealImagPtr(
    ffi.Pointer<ffi.Double> realPtr,
    ffi.Pointer<ffi.Double> imagPtr,
    int length,
  ) {
    final values = Float64x2List(length);
    for (int i = 0; i < length; i++) {
      values[i] = Float64x2(realPtr[i], imagPtr[i]);
    }
    return Complex64List.wrap(values);
  }

  /// Number of complex elements.
  int get length => _values.length;

  /// Returns the real part at index [i].
  double realAt(int i) => _values[i].x;

  /// Returns the imaginary part at index [i].
  double imagAt(int i) => _values[i].y;

  /// Sets the complex value at index [i].
  void set(int i, double re, double im) {
    _values[i] = Float64x2(re, im);
  }

  /// Returns the real part as a new list.
  Float64List get real => realCopy();

  /// Returns the imaginary part as a new list.
  Float64List get imag => imagCopy();

  /// Returns a copy of the real part.
  Float64List realCopy() {
    final out = Float64List(length);
    for (int i = 0; i < length; i++) {
      out[i] = _values[i].x;
    }
    return out;
  }

  /// Returns a copy of the imaginary part.
  Float64List imagCopy() {
    final out = Float64List(length);
    for (int i = 0; i < length; i++) {
      out[i] = _values[i].y;
    }
    return out;
  }

  /// Returns a new [Complex64List] that is the conjugate of this list.
  Complex64List conj() {
    final out = Float64x2List(length);
    for (int i = 0; i < length; i++) {
      final v = _values[i];
      out[i] = Float64x2(v.x, -v.y);
    }
    return Complex64List.wrap(out);
  }

  /// Returns the magnitude (absolute value) of each complex element.
  Float64List abs() {
    final out = Float64List(length);
    for (int i = 0; i < length; i++) {
      final v = _values[i];
      out[i] = math.sqrt((v.x * v.x) + (v.y * v.y));
    }
    return out;
  }

  /// Returns the squared magnitude of each complex element.
  Float64List abs2() {
    final out = Float64List(length);
    for (int i = 0; i < length; i++) {
      final v = _values[i];
      out[i] = (v.x * v.x) + (v.y * v.y);
    }
    return out;
  }

  /// Returns the phase angle (argument) of each complex element.
  Float64List angle() {
    final out = Float64List(length);
    for (int i = 0; i < length; i++) {
      final v = _values[i];
      out[i] = math.atan2(v.y, v.x);
    }
    return out;
  }

  /// Multiplies all complex values by a real scalar [gain].
  void scale(double gain) {
    for (int i = 0; i < length; i++) {
      final v = _values[i];
      _values[i] = Float64x2(v.x * gain, v.y * gain);
    }
  }

  /// In-place complex conjugation.
  void conjInPlace() {
    for (int i = 0; i < length; i++) {
      final v = _values[i];
      _values[i] = Float64x2(v.x, -v.y);
    }
  }

  @override
  String toString() => 'Complex64List(length: $length)';
}
