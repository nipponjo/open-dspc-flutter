import 'dart:typed_data';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import '../utils/native_handle.dart';

import '../bindings/open_dspc_bindings_generated.dart'
    show
        yl_resample_ctx_create,
        yl_resample_ctx_destroy,
        yl_resample_ctx_process,
        yl_resample_out_len_ffi,
        yl_resample_reset_ffi;

enum ResamplingMethod {
  /// Sinc interpolation using a Hann-windowed low-pass kernel.
  sincHann(1),

  /// Sinc interpolation using a Kaiser-windowed low-pass kernel.
  sincKaiser(2);

  const ResamplingMethod(this.value);
  final int value;
}

/// Convenience API for one-off resampling operations.
///
/// Use this when you only need to resample a single block and do not want to
/// retain native state between calls.
class Resample {
  const Resample._();

  /// Resamples a single block of audio from [origFreq] to [newFreq].
  ///
  /// This is a convenience one-shot API:
  /// - creates a native resampling context,
  /// - processes [input],
  /// - returns a newly allocated output buffer,
  /// - destroys the native context before returning.
  ///
  /// [lowpassFilterWidth] controls the interpolation filter width.
  /// Higher values can improve quality at the cost of more computation.
  ///
  /// [rolloff] sets the low-pass cutoff as a fraction of the Nyquist rate.
  ///
  /// [method] selects the windowing/resampling kernel.
  /// If [method] is [ResamplingMethod.sincKaiser], [beta] controls the
  /// Kaiser window shape.
  ///
  /// Throws a [StateError] if the native resampling context cannot be created.
  static Float32List process(
    Float32List input, {
    required int origFreq,
    required int newFreq,
    int lowpassFilterWidth = 6,
    double rolloff = 0.99,
    ResamplingMethod method = ResamplingMethod.sincHann,
    double? beta,
  }) {
    final L = input.length;
    final ctx = yl_resample_ctx_create(
      origFreq,
      newFreq,
      lowpassFilterWidth,
      rolloff,
      method.value,
      beta ?? 0,
    );
    if (ctx == ffi.nullptr) {
      throw StateError("Failed to create resampling context");
    }

    ffi.Pointer<ffi.Float> inPtr = ffi.nullptr;
    ffi.Pointer<ffi.Float> outPtr = ffi.nullptr;
    try {
      final outLen = yl_resample_out_len_ffi(origFreq, newFreq, L);
      inPtr = calloc<ffi.Float>(L);
      outPtr = calloc<ffi.Float>(outLen);
      inPtr.asTypedList(L).setAll(0, input);
      // double errorSqrt = yl_lpc_ctx_process_frame(ctx, inPtr, L, 0, outPtr);
      yl_resample_ctx_process(ctx, inPtr, L, outPtr);

      final out = Float32List(outLen);
      out.setAll(0, outPtr.asTypedList(outLen));
      return out;
    } finally {
      if (inPtr != ffi.nullptr) calloc.free(inPtr);
      if (outPtr != ffi.nullptr) calloc.free(outPtr);
      yl_resample_ctx_destroy(ctx);
    }
  }
}

final class _ResamplerResource implements NativeResource {
  /// Internal FFI context and cached buffers for a reusable resampler.
  final ffi.Pointer<ffi.Void> ctx;
  ffi.Pointer<ffi.Float> inPtr;
  ffi.Pointer<ffi.Float> outPtr;
  int inCapacity;
  int outCapacity;

  _ResamplerResource(this.ctx)
    : inPtr = ffi.nullptr,
      outPtr = ffi.nullptr,
      inCapacity = 0,
      outCapacity = 0;

  @override
  void free() {
    if (inPtr != ffi.nullptr) calloc.free(inPtr);
    if (outPtr != ffi.nullptr) calloc.free(outPtr);
    yl_resample_ctx_destroy(ctx);
  }
}

/// Reusable native resampler with cached context and buffers.
///
/// Unlike [Resample.process], this class creates the native resampling context
/// once and reuses it across multiple calls to [process] or [processInto].
/// This avoids repeated native setup and buffer allocation when resampling many
/// blocks with the same configuration.
///
/// The native context is released by [close]. If [close] is not called, cleanup
/// is still attempted by the finalizer inherited from [NativeHandle], but
/// callers should prefer explicit disposal.
///
/// Example:
/// ```dart
/// final resampler = Resampler(origFreq: 16000, newFreq: 8000);
///
/// final x1 = SignalGenerator.sine(
///   n: 1024,
///   freqHz: 440.0,
///   sampleRate: 16000.0,
/// );
/// final y1 = resampler.process(x1);
///
/// final x2 = SignalGenerator.sine(
///   n: 2048,
///   freqHz: 880.0,
///   sampleRate: 16000.0,
/// );
/// final out = Float32List(resampler.outLenFor(x2.length));
/// final written = resampler.processInto(x2, out);
/// final y2 = out.sublist(0, written);
///
/// resampler.close();
/// ```
///
/// Use [reset] if you want to reset native state between calls.
/// Use [outLenFor] to compute the required output buffer size for a given input.
class Resampler extends NativeHandle<_ResamplerResource> {
  final int origFreq;
  final int newFreq;
  final int lowpassFilterWidth;
  final double rolloff;
  final ResamplingMethod method;
  final double? beta;

  /// Internal constructor used by [Resampler] to wrap an initialized native context.
  Resampler._(
    _ResamplerResource res, {
    required this.origFreq,
    required this.newFreq,
    required this.lowpassFilterWidth,
    required this.rolloff,
    required this.method,
    required this.beta,
  }) : super(res);

  /// Creates and owns a reusable resampling context for repeated calls.
  ///
  /// The context is initialized once and kept alive until [close] is called.
  factory Resampler({
    required int origFreq,
    required int newFreq,
    int lowpassFilterWidth = 6,
    double rolloff = 0.99,
    ResamplingMethod method = ResamplingMethod.sincHann,
    double? beta,
  }) {
    final ctx = yl_resample_ctx_create(
      origFreq,
      newFreq,
      lowpassFilterWidth,
      rolloff,
      method.value,
      beta ?? 0,
    );
    if (ctx == ffi.nullptr) {
      throw StateError('Failed to create resampling context');
    }

    return Resampler._(
      _ResamplerResource(ctx),
      origFreq: origFreq,
      newFreq: newFreq,
      lowpassFilterWidth: lowpassFilterWidth,
      rolloff: rolloff,
      method: method,
      beta: beta,
    );
  }

  /// Returns the output length for an input block of [inputLength] samples.
  int outLenFor(int inputLength) {
    return yl_resample_out_len_ffi(origFreq, newFreq, inputLength);
  }

  /// Resets native resampling state for subsequent calls on the same instance.
  void reset() {
    yl_resample_reset_ffi(res.ctx);
  }

  /// Releases any cached input/output scratch buffers while keeping the context.
  void freeBuffers() {
    final r = res;
    if (r.inPtr != ffi.nullptr) {
      calloc.free(r.inPtr);
      r.inPtr = ffi.nullptr;
    }
    if (r.outPtr != ffi.nullptr) {
      calloc.free(r.outPtr);
      r.outPtr = ffi.nullptr;
    }
    r.inCapacity = 0;
    r.outCapacity = 0;
  }

  /// Ensures the internal input scratch buffer can hold at least [length] samples.
  void _ensureInputCapacity(int length) {
    final r = res;
    if (length <= r.inCapacity) return;
    if (r.inPtr != ffi.nullptr) calloc.free(r.inPtr);
    r.inPtr = calloc<ffi.Float>(length);
    r.inCapacity = length;
  }

  /// Ensures the internal output scratch buffer can hold at least [length] samples.
  void _ensureOutputCapacity(int length) {
    final r = res;
    if (length <= r.outCapacity) return;
    if (r.outPtr != ffi.nullptr) calloc.free(r.outPtr);
    r.outPtr = calloc<ffi.Float>(length);
    r.outCapacity = length;
  }

  /// Resamples [input] using the cached native context and reusable buffers.
  ///
  /// The returned [Float32List] is a fresh Dart allocation containing the
  /// resampled signal. Native plan state and FFI buffers are retained for
  /// subsequent calls.
  Float32List process(Float32List input) {
    final inLen = input.length;
    final outLen = outLenFor(inLen);
    final r = res;

    _ensureInputCapacity(inLen);
    _ensureOutputCapacity(outLen);

    r.inPtr.asTypedList(inLen).setAll(0, input);
    yl_resample_ctx_process(r.ctx, r.inPtr, inLen, r.outPtr);

    return Float32List.fromList(r.outPtr.asTypedList(outLen));
  }

  /// Zero-allocation output API for repeated use.
  ///
  /// [out] must have length >= [outLenFor]`(input.length)`.
  /// Returns the number of output samples written.
  int processInto(Float32List input, Float32List out) {
    final inLen = input.length;
    final outLen = outLenFor(inLen);
    final r = res;

    if (out.length < outLen) {
      throw ArgumentError('out length ${out.length} < required $outLen');
    }

    _ensureInputCapacity(inLen);
    _ensureOutputCapacity(outLen);

    r.inPtr.asTypedList(inLen).setAll(0, input);
    yl_resample_ctx_process(r.ctx, r.inPtr, inLen, r.outPtr);
    out.setRange(0, outLen, r.outPtr.asTypedList(outLen));
    return outLen;
  }
}
