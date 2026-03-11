import 'dart:ffi' as ffi;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import '../utils/native_handle.dart';
import '../utils/types.dart';

import '../bindings/open_dspc_bindings_generated.dart'
    show
        yl_fft_plan_c2c_create,
        yl_fft_plan_c2r_create,
        yl_fft_plan_destroy,
        yl_fft_plan_execute_c2c_backward,
        yl_fft_plan_execute_c2c_forward,
        yl_fft_plan_execute_c2r,
        yl_fft_plan_execute_r2c,
        yl_fft_plan_execute_r2c_spec,
        yl_fft_plan_r2c_create,
        yl_rfft_bins;

/// Output representation for scalar spectra.
///
/// Used by [FFTStatic.rfftMag], [RfftPlan.executeSpec], and
/// [RfftPlan.executeSpecInto].
enum SpecMode {
  /// Magnitude spectrum: `sqrt(re^2 + im^2)`.
  mag(1),

  /// Power spectrum: `re^2 + im^2`.
  power(2),

  /// Log-power spectrum in dB with floor clipping.
  db(3);

  const SpecMode(this.value);
  final int value;
}

/// One-shot static FFT utilities.
///
/// This class creates and destroys native FFT plans per call. For repeated
/// transforms at a fixed length, prefer [RfftPlan] or [CfftPlan] to avoid
/// repeated allocation and planning overhead.
///
/// Example:
/// ```dart
/// import 'dart:typed_data';
/// import 'package:open_dspc/open_dspc.dart';
///
/// final x = SignalGenerator.sine(n: 1024, freqHz: 440, sampleRate: 16000);
///
/// final spec = FFTStatic.rfft(x);
/// final mag = FFTStatic.rfftMag(x, mode: SpecMode.mag);
/// final y = FFTStatic.irfft(spec.real, spec.imag);
/// ```
class FFTStatic {
  const FFTStatic._();

  /// Computes the complex forward FFT of a complex-valued input signal.
  ///
  /// [real] and [imag] hold the real and imaginary parts of the input and are
  /// interpreted as a length-[n] complex sequence. If [n] is omitted, the
  /// transform length defaults to `real.length`.
  ///
  /// When [n] is larger than the input length, the input is zero-padded.
  /// When [n] is smaller, the input is truncated to the first [n] samples.
  ///
  /// Returns a complex spectrum of length [n].
  static Complex32List fft(Float32List real, Float32List imag, {int? n}) {
    n = n ?? real.length;

    final plan = yl_fft_plan_c2c_create(n);
    if (plan == ffi.nullptr) {
      throw StateError('yl_fft_plan_c2c_create($n) returned nullptr');
    }

    ffi.Pointer<ffi.Float> realInPtr = ffi.nullptr;
    ffi.Pointer<ffi.Float> imagInPtr = ffi.nullptr;
    ffi.Pointer<ffi.Float> realOutPtr = ffi.nullptr;
    ffi.Pointer<ffi.Float> imagOutPtr = ffi.nullptr;
    try {
      realInPtr = calloc<ffi.Float>(n);
      imagInPtr = calloc<ffi.Float>(n);
      realOutPtr = calloc<ffi.Float>(n);
      imagOutPtr = calloc<ffi.Float>(n);

      final copyLen = math.min(real.length, n);
      realInPtr.asTypedList(n).setRange(0, copyLen, real);
      imagInPtr.asTypedList(n).setRange(0, copyLen, imag);

      yl_fft_plan_execute_c2c_forward(
        plan,
        realInPtr,
        imagInPtr,
        realOutPtr,
        imagOutPtr,
      );

      return Complex32List.fromRealImagPtr(realOutPtr, imagOutPtr, n);
    } finally {
      if (realInPtr != ffi.nullptr) calloc.free(realInPtr);
      if (imagInPtr != ffi.nullptr) calloc.free(imagInPtr);
      if (realOutPtr != ffi.nullptr) calloc.free(realOutPtr);
      if (imagOutPtr != ffi.nullptr) calloc.free(imagOutPtr);
      yl_fft_plan_destroy(plan);
    }
  }

  /// Computes the complex inverse FFT of a complex spectrum.
  ///
  /// [real] and [imag] hold the real and imaginary parts of the input spectrum
  /// and are interpreted as a length-[n] complex sequence. If [n] is omitted,
  /// the transform length defaults to `real.length`.
  ///
  /// When [n] is larger than the input length, the spectrum is zero-padded.
  /// When [n] is smaller, the spectrum is truncated to the first [n] bins.
  ///
  /// Returns a complex time-domain sequence of length [n]. The native inverse
  /// path is normalized, so no extra `1 / n` scaling is required.
  static Complex32List ifft(Float32List real, Float32List imag, {int? n}) {
    n = n ?? real.length;

    final plan = yl_fft_plan_c2c_create(n);
    if (plan == ffi.nullptr) {
      throw StateError('yl_fft_plan_c2c_create($n) returned nullptr');
    }

    ffi.Pointer<ffi.Float> realInPtr = ffi.nullptr;
    ffi.Pointer<ffi.Float> imagInPtr = ffi.nullptr;
    ffi.Pointer<ffi.Float> realOutPtr = ffi.nullptr;
    ffi.Pointer<ffi.Float> imagOutPtr = ffi.nullptr;
    try {
      realInPtr = calloc<ffi.Float>(n);
      imagInPtr = calloc<ffi.Float>(n);
      realOutPtr = calloc<ffi.Float>(n);
      imagOutPtr = calloc<ffi.Float>(n);

      final copyLen = math.min(real.length, n);
      realInPtr.asTypedList(n).setRange(0, copyLen, real);
      imagInPtr.asTypedList(n).setRange(0, copyLen, imag);

      yl_fft_plan_execute_c2c_backward(
        plan,
        realInPtr,
        imagInPtr,
        realOutPtr,
        imagOutPtr,
      );

      return Complex32List.fromRealImagPtr(realOutPtr, imagOutPtr, n);
    } finally {
      if (realInPtr != ffi.nullptr) calloc.free(realInPtr);
      if (imagInPtr != ffi.nullptr) calloc.free(imagInPtr);
      if (realOutPtr != ffi.nullptr) calloc.free(realOutPtr);
      if (imagOutPtr != ffi.nullptr) calloc.free(imagOutPtr);
      yl_fft_plan_destroy(plan);
    }
  }

  /// Computes the real-to-complex FFT of a real-valued input signal.
  ///
  /// If [n] is omitted, the transform length defaults to `input.length`.
  /// When [n] is larger than the input length, the input is zero-padded.
  /// When [n] is smaller, the input is truncated to the first [n] samples.
  ///
  /// Returns the non-redundant positive-frequency spectrum with
  /// `n ~/ 2 + 1` complex bins.
  static Complex32List rfft(Float32List input, {int? n}) {
    n = n ?? input.length;
    final bins = yl_rfft_bins(n);

    final plan = yl_fft_plan_r2c_create(n);
    if (plan == ffi.nullptr) {
      throw StateError('yl_fft_plan_r2c_create($n) returned nullptr');
    }

    ffi.Pointer<ffi.Float> inPtr = ffi.nullptr;
    ffi.Pointer<ffi.Float> realOutPtr = ffi.nullptr;
    ffi.Pointer<ffi.Float> imagOutPtr = ffi.nullptr;
    try {
      inPtr = calloc<ffi.Float>(n);
      realOutPtr = calloc<ffi.Float>(bins);
      imagOutPtr = calloc<ffi.Float>(bins);

      final copyLen = math.min(input.length, n);
      inPtr.asTypedList(n).setRange(0, copyLen, input);

      yl_fft_plan_execute_r2c(plan, inPtr, realOutPtr, imagOutPtr);

      return Complex32List.fromRealImagPtr(realOutPtr, imagOutPtr, bins);
    } finally {
      if (inPtr != ffi.nullptr) calloc.free(inPtr);
      if (realOutPtr != ffi.nullptr) calloc.free(realOutPtr);
      if (imagOutPtr != ffi.nullptr) calloc.free(imagOutPtr);
      yl_fft_plan_destroy(plan);
    }
  }

  /// Computes the inverse real FFT from a packed positive-frequency spectrum.
  ///
  /// [real] and [imag] must contain the non-redundant `rfft` spectrum:
  /// DC, positive frequencies, and Nyquist when [n] is even.
  ///
  /// If [n] is omitted, the output length is inferred as `2 * (bins - 1)`,
  /// where `bins == real.length`. This matches the common FFT convention for
  /// reconstructing a real signal from an `rfft` result.
  ///
  /// If [n] is provided, it is interpreted as the real-domain output length.
  /// The expected packed spectrum length then becomes `n ~/ 2 + 1`. Inputs are
  /// truncated or zero-padded to that packed length before the inverse transform.
  ///
  /// Returns a real-valued time-domain signal of length [n].
  static Float32List irfft(Float32List real, Float32List imag, {int? n}) {
    if (real.length != imag.length) {
      throw ArgumentError('real and imag must have the same length');
    }

    final inputBins = real.length;
    final outLen = n ?? (2 * (inputBins - 1));
    final bins = yl_rfft_bins(outLen);

    final plan = yl_fft_plan_c2r_create(outLen);
    if (plan == ffi.nullptr) {
      throw StateError('yl_fft_plan_c2r_create($outLen) returned nullptr');
    }

    ffi.Pointer<ffi.Float> realInPtr = ffi.nullptr;
    ffi.Pointer<ffi.Float> imagInPtr = ffi.nullptr;
    ffi.Pointer<ffi.Float> realOutPtr = ffi.nullptr;

    try {
      realInPtr = calloc<ffi.Float>(bins);
      imagInPtr = calloc<ffi.Float>(bins);
      realOutPtr = calloc<ffi.Float>(outLen);

      final copyLen = math.min(real.length, bins);
      realInPtr.asTypedList(bins).setRange(0, copyLen, real);
      imagInPtr.asTypedList(bins).setRange(0, copyLen, imag);

      final outReal = Float32List(outLen);

      yl_fft_plan_execute_c2r(plan, realInPtr, imagInPtr, realOutPtr);

      outReal.setAll(0, realOutPtr.asTypedList(outLen));

      return outReal;
    } finally {
      if (realInPtr != ffi.nullptr) calloc.free(realInPtr);
      if (imagInPtr != ffi.nullptr) calloc.free(imagInPtr);
      if (realOutPtr != ffi.nullptr) calloc.free(realOutPtr);
      yl_fft_plan_destroy(plan);
    }
  }

  /// Computes a real-input magnitude, power, or dB spectrum.
  ///
  /// If [n] is omitted, the transform length defaults to `input.length`.
  /// When [n] is larger than the input length, the input is zero-padded.
  /// When [n] is smaller, the input is truncated to the first [n] samples.
  ///
  /// Returns `n ~/ 2 + 1` bins.
  static Float32List rfftMag(
    Float32List input, {
    int? n,
    SpecMode mode = SpecMode.mag,
    double dbFloor = -120,
  }) {
    n = n ?? input.length;
    final bins = yl_rfft_bins(n);

    final plan = yl_fft_plan_r2c_create(n);
    if (plan == ffi.nullptr) {
      throw StateError('yl_fft_plan_r2c_create($n) returned nullptr');
    }

    ffi.Pointer<ffi.Float> inPtr = ffi.nullptr;
    ffi.Pointer<ffi.Float> specPtr = ffi.nullptr;

    try {
      inPtr = calloc<ffi.Float>(n);
      specPtr = calloc<ffi.Float>(bins);

      final copyLen = math.min(input.length, n);
      inPtr.asTypedList(n).setRange(0, copyLen, input);

      // allocate output Dart list
      final out = Float32List(bins);

      yl_fft_plan_execute_r2c_spec(plan, inPtr, specPtr, mode.value, dbFloor);

      out.setAll(0, specPtr.asTypedList(bins));
      return out;
    } finally {
      if (inPtr != ffi.nullptr) calloc.free(inPtr);
      if (specPtr != ffi.nullptr) calloc.free(specPtr);
      yl_fft_plan_destroy(plan);
    }
  }
}

final class _RfftPlanResource implements NativeResource {
  final ffi.Pointer<ffi.Void> plan;
  final ffi.Pointer<ffi.Float> input;
  final ffi.Pointer<ffi.Float> re;
  final ffi.Pointer<ffi.Float> im;
  final ffi.Pointer<ffi.Float> spec;

  _RfftPlanResource(this.plan, this.input, this.re, this.im, this.spec);

  @override
  void free() {
    yl_fft_plan_destroy(plan);
    calloc.free(input);
    calloc.free(re);
    calloc.free(im);
    calloc.free(spec);
  }
}

/// Reusable real-input FFT plan (`r2c`) with internal native buffers.
///
/// Instances manage a native plan and associated scratch/output storage.
/// Call [close] when the plan is no longer needed to release native memory.
///
/// Example:
/// ```dart
/// import 'dart:typed_data';
/// import 'package:open_dspc/open_dspc.dart';
///
/// final plan = RfftPlan(1024);
/// try {
///   final x = SignalGenerator.sine(n: 1024, freqHz: 440, sampleRate: 16000);
///   final z = plan.execute(x); // Complex32List backed by plan.re/plan.im
///   final db = plan.executeSpec(x, mode: SpecMode.db, dbFloor: -120);
///
///   final outRe = Float32List(plan.bins);
///   final outIm = Float32List(plan.bins);
///   plan.executeInto(x, outRe, outIm);
/// } finally {
///   plan.close();
/// }
/// ```
class RfftPlan extends NativeHandle<_RfftPlanResource> {
  /// FFT length used by this plan.
  final int n;

  /// Number of non-redundant bins (`n ~/ 2 + 1`).
  final int bins;

  /// Reusable real-part output buffer for [execute].
  final Float32List re;

  /// Reusable imaginary-part output buffer for [execute].
  final Float32List im;

  /// Reusable scalar spectrum buffer for [executeSpec].
  final Float32List spec;

  RfftPlan._(this.n, this.bins, _RfftPlanResource res)
    : re = Float32List(bins),
      im = Float32List(bins),
      spec = Float32List(bins),
      super(res);

  /// Creates a reusable `r2c` FFT plan for transform length [n].
  ///
  /// Throws [ArgumentError] if [n] is not positive.
  /// Throws [StateError] if native plan creation fails.
  factory RfftPlan(int n) {
    if (n <= 0) throw ArgumentError.value(n, 'n', 'must be > 0');

    final plan = yl_fft_plan_r2c_create(n);
    if (plan == ffi.nullptr) {
      throw StateError('yl_fft_plan_r2c_create($n) returned nullptr');
    }

    final bins = yl_rfft_bins(n);

    ffi.Pointer<ffi.Float>? inputPtr, rePtr, imPtr, specPtr;
    try {
      inputPtr = calloc<ffi.Float>(n);
      rePtr = calloc<ffi.Float>(bins);
      imPtr = calloc<ffi.Float>(bins);
      specPtr = calloc<ffi.Float>(bins);

      return RfftPlan._(
        n,
        bins,
        _RfftPlanResource(plan, inputPtr, rePtr, imPtr, specPtr),
      );
    } catch (_) {
      if (inputPtr != null) calloc.free(inputPtr);
      if (rePtr != null) calloc.free(rePtr);
      if (imPtr != null) calloc.free(imPtr);
      if (specPtr != null) calloc.free(specPtr);
      yl_fft_plan_destroy(plan);
      rethrow;
    }
  }

  void _loadInput(Float32List input) {
    final r = res;
    final inputView = r.input.asTypedList(n);
    inputView.fillRange(0, n, 0.0);
    final copyLen = math.min(input.length, n);
    inputView.setRange(0, copyLen, input);
  }

  /// Computes the non-redundant complex spectrum of a real-valued input frame.
  ///
  /// Example:
  /// ```dart
  /// final z = plan.execute(frame);
  /// print('DC = ${z.realAt(0)}');
  /// ```
  Complex32List execute(Float32List input) {
    final r = res;
    _loadInput(input);
    yl_fft_plan_execute_r2c(r.plan, r.input, r.re, r.im);

    re.setAll(0, r.re.asTypedList(bins));
    im.setAll(0, r.im.asTypedList(bins));

    return Complex32List.wrap(re, im);
  }

  /// Computes a magnitude, power, or dB spectrum into the reusable [spec] buffer.
  ///
  /// Example:
  /// ```dart
  /// final power = plan.executeSpec(frame, mode: SpecMode.power);
  /// ```
  Float32List executeSpec(
    Float32List input, {
    SpecMode mode = SpecMode.power,
    double dbFloor = -120.0,
  }) {
    final r = res;
    _loadInput(input);
    yl_fft_plan_execute_r2c_spec(r.plan, r.input, r.spec, mode.value, dbFloor);

    spec.setAll(0, r.spec.asTypedList(bins));
    return spec;
  }

  /// Zero-allocation API: caller provides output buffers for the complex spectrum.
  ///
  /// Example:
  /// ```dart
  /// final outRe = Float32List(plan.bins);
  /// final outIm = Float32List(plan.bins);
  /// plan.executeInto(frame, outRe, outIm);
  /// ```
  void executeInto(Float32List input, Float32List outRe, Float32List outIm) {
    if (outRe.length != bins) {
      throw ArgumentError('outRe length ${outRe.length} != bins $bins');
    }
    if (outIm.length != bins) {
      throw ArgumentError('outIm length ${outIm.length} != bins $bins');
    }

    final r = res;
    _loadInput(input);
    yl_fft_plan_execute_r2c(r.plan, r.input, r.re, r.im);

    outRe.setAll(0, r.re.asTypedList(bins));
    outIm.setAll(0, r.im.asTypedList(bins));
  }

  /// Zero-allocation API: caller provides output storage for the scalar spectrum.
  ///
  /// Example:
  /// ```dart
  /// final outBins = Float32List(plan.bins);
  /// plan.executeSpecInto(frame, outBins, mode: SpecMode.mag);
  /// ```
  void executeSpecInto(
    Float32List input,
    Float32List outBins, {
    SpecMode mode = SpecMode.power,
    double dbFloor = -120.0,
  }) {
    if (outBins.length != bins) {
      throw ArgumentError('outBins length ${outBins.length} != bins $bins');
    }

    final r = res;
    _loadInput(input);
    yl_fft_plan_execute_r2c_spec(r.plan, r.input, r.spec, mode.value, dbFloor);

    outBins.setAll(0, r.spec.asTypedList(bins));
  }
}

final class _CfftPlanResource implements NativeResource {
  final ffi.Pointer<ffi.Void> plan;
  final ffi.Pointer<ffi.Float> inReal;
  final ffi.Pointer<ffi.Float> inImag;
  final ffi.Pointer<ffi.Float> outReal;
  final ffi.Pointer<ffi.Float> outImag;

  _CfftPlanResource(
    this.plan,
    this.inReal,
    this.inImag,
    this.outReal,
    this.outImag,
  );

  @override
  void free() {
    yl_fft_plan_destroy(plan);
    calloc.free(inReal);
    calloc.free(inImag);
    calloc.free(outReal);
    calloc.free(outImag);
  }
}

/// Reusable complex-input FFT plan (`c2c`) with internal native buffers.
///
/// Instances support both forward ([fft]) and inverse ([ifft]) transforms
/// at a fixed transform size [n]. Call [close] to release native memory.
///
/// Example:
/// ```dart
/// import 'dart:typed_data';
/// import 'package:open_dspc/open_dspc.dart';
///
/// final plan = CfftPlan(1024);
/// try {
///   final re = SignalGenerator.sine(n: 1024, freqHz: 440, sampleRate: 16000);
///   final im = Float32List(1024);
///   final z = plan.fft(re, im);
///   final x = plan.ifft(z.real, z.imag);
/// } finally {
///   plan.close();
/// }
/// ```
class CfftPlan extends NativeHandle<_CfftPlanResource> {
  /// FFT length used by this plan.
  final int n;

  /// Reusable real-part output buffer for [fft] and [ifft].
  final Float32List real;

  /// Reusable imaginary-part output buffer for [fft] and [ifft].
  final Float32List imag;

  CfftPlan._(this.n, _CfftPlanResource res)
    : real = Float32List(n),
      imag = Float32List(n),
      super(res);

  /// Creates a reusable `c2c` FFT plan for transform length [n].
  ///
  /// Throws [ArgumentError] if [n] is not positive.
  /// Throws [StateError] if native plan creation fails.
  factory CfftPlan(int n) {
    if (n <= 0) throw ArgumentError.value(n, 'n', 'must be > 0');

    final plan = yl_fft_plan_c2c_create(n);
    if (plan == ffi.nullptr) {
      throw StateError('yl_fft_plan_c2c_create($n) returned nullptr');
    }

    ffi.Pointer<ffi.Float>? inRealPtr, inImagPtr, outRealPtr, outImagPtr;
    try {
      inRealPtr = calloc<ffi.Float>(n);
      inImagPtr = calloc<ffi.Float>(n);
      outRealPtr = calloc<ffi.Float>(n);
      outImagPtr = calloc<ffi.Float>(n);

      return CfftPlan._(
        n,
        _CfftPlanResource(plan, inRealPtr, inImagPtr, outRealPtr, outImagPtr),
      );
    } catch (_) {
      if (inRealPtr != null) calloc.free(inRealPtr);
      if (inImagPtr != null) calloc.free(inImagPtr);
      if (outRealPtr != null) calloc.free(outRealPtr);
      if (outImagPtr != null) calloc.free(outImagPtr);
      yl_fft_plan_destroy(plan);
      rethrow;
    }
  }

  void _loadInput(Float32List inRe, Float32List inIm) {
    final r = res;
    final reView = r.inReal.asTypedList(n);
    final imView = r.inImag.asTypedList(n);
    reView.fillRange(0, n, 0.0);
    imView.fillRange(0, n, 0.0);

    final copyRe = math.min(inRe.length, n);
    final copyIm = math.min(inIm.length, n);
    reView.setRange(0, copyRe, inRe);
    imView.setRange(0, copyIm, inIm);
  }

  /// Computes the complex forward FFT into the reusable [real]/[imag] buffers.
  ///
  /// Example:
  /// ```dart
  /// final z = plan.fft(inRe, inIm);
  /// ```
  Complex32List fft(Float32List inRe, Float32List inIm) {
    final r = res;
    _loadInput(inRe, inIm);
    yl_fft_plan_execute_c2c_forward(
      r.plan,
      r.inReal,
      r.inImag,
      r.outReal,
      r.outImag,
    );

    real.setAll(0, r.outReal.asTypedList(n));
    imag.setAll(0, r.outImag.asTypedList(n));

    return Complex32List.wrap(real, imag);
  }

  /// Computes the complex inverse FFT into the reusable [real]/[imag] buffers.
  ///
  /// Example:
  /// ```dart
  /// final x = plan.ifft(specRe, specIm);
  /// ```
  Complex32List ifft(Float32List inRe, Float32List inIm) {
    final r = res;
    _loadInput(inRe, inIm);
    yl_fft_plan_execute_c2c_backward(
      r.plan,
      r.inReal,
      r.inImag,
      r.outReal,
      r.outImag,
    );

    real.setAll(0, r.outReal.asTypedList(n));
    imag.setAll(0, r.outImag.asTypedList(n));

    return Complex32List.wrap(real, imag);
  }

  /// Zero-allocation forward complex FFT into caller-provided output buffers.
  ///
  /// Example:
  /// ```dart
  /// plan.fftInto(inRe, inIm, outRe, outIm);
  /// ```
  void fftInto(
    Float32List inRe,
    Float32List inIm,
    Float32List outRe,
    Float32List outIm,
  ) {
    if (outRe.length != n || outIm.length != n) {
      throw ArgumentError('output lengths must both equal n $n');
    }

    final r = res;
    _loadInput(inRe, inIm);
    yl_fft_plan_execute_c2c_forward(
      r.plan,
      r.inReal,
      r.inImag,
      r.outReal,
      r.outImag,
    );

    outRe.setAll(0, r.outReal.asTypedList(n));
    outIm.setAll(0, r.outImag.asTypedList(n));
  }

  /// Zero-allocation inverse complex FFT into caller-provided output buffers.
  ///
  /// Example:
  /// ```dart
  /// plan.ifftInto(specRe, specIm, outRe, outIm);
  /// ```
  void ifftInto(
    Float32List inRe,
    Float32List inIm,
    Float32List outRe,
    Float32List outIm,
  ) {
    if (outRe.length != n || outIm.length != n) {
      throw ArgumentError('output lengths must both equal n $n');
    }

    final r = res;
    _loadInput(inRe, inIm);
    yl_fft_plan_execute_c2c_backward(
      r.plan,
      r.inReal,
      r.inImag,
      r.outReal,
      r.outImag,
    );

    outRe.setAll(0, r.outReal.asTypedList(n));
    outIm.setAll(0, r.outImag.asTypedList(n));
  }
}
