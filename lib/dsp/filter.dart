import 'dart:typed_data';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

import '../bindings/open_dspc_bindings_generated.dart'
    show yl_iir_ctx_create_df2t_f32, yl_iir_ctx_process_f32, yl_iir_ctx_destroy;

class Filter {
  const Filter._();

  /// Applies a causal linear digital filter (IIR/FIR) to `input`.
  ///
  /// The implemented difference equation is:
  /// `a[0] * y[n] = sum_{k=0..nb-1} b[k] * x[n-k] - sum_{k=1..na-1} a[k] * y[n-k]`
  ///
  /// Conventions:
  /// - `b` are feed-forward (numerator) coefficients.
  /// - `a` are feedback (denominator) coefficients.
  /// - `a[0]` must be non-zero.
  ///
  /// Z-domain form:
  /// ```text
  ///                     -1              -M
  ///         b[0] + b[1]z  + ... + b[M] z
  /// Y(z) = -------------------------------- X(z)
  ///                     -1              -N
  ///         a[0] + a[1]z  + ... + a[N] z
  /// ```
  ///
  /// Behavior:
  /// - Uses a direct-form II transposed stateful core in native code.
  /// - Returns one output sample per input sample (`out.length == input.length`).
  /// - If `out` is provided, it is filled in-place and returned.
  static Float32List lfilter(
    Float32List input, {
    required Float32List b,
    required Float32List a,
    Float32List? out,
  }) {
    final L = input.length;
    final nb = b.length;
    final na = a.length;

    ffi.Pointer<ffi.Float> bPtr = ffi.nullptr;
    ffi.Pointer<ffi.Float> aPtr = ffi.nullptr;
    try {
      aPtr = calloc<ffi.Float>(na);
      bPtr = calloc<ffi.Float>(nb);
      aPtr.asTypedList(L).setAll(0, a);
      bPtr.asTypedList(L).setAll(0, b);
    } catch (_) {
      if (bPtr != ffi.nullptr) calloc.free(bPtr);
      if (aPtr != ffi.nullptr) calloc.free(aPtr);
      throw StateError("Failed to create lfilter context");
    }

    final ctx = yl_iir_ctx_create_df2t_f32(bPtr, nb, aPtr, na);
    if (ctx == ffi.nullptr) {
      throw StateError("Failed to create lfilter context");
    }
    ffi.Pointer<ffi.Float> inPtr = ffi.nullptr;
    ffi.Pointer<ffi.Float> outPtr = ffi.nullptr;
    try {
      inPtr = calloc<ffi.Float>(L);
      outPtr = calloc<ffi.Float>(L);
      inPtr.asTypedList(L).setAll(0, input);
      // double errorSqrt = yl_lpc_ctx_process_frame(ctx, inPtr, L, 0, outPtr);
      yl_iir_ctx_process_f32(ctx, inPtr, outPtr, L);

      out = out ?? Float32List(L);
      out.setAll(0, outPtr.asTypedList(L));
      return out;
    } finally {
      if (inPtr != ffi.nullptr) calloc.free(inPtr);
      if (outPtr != ffi.nullptr) calloc.free(outPtr);
      if (bPtr != ffi.nullptr) calloc.free(bPtr);
      if (aPtr != ffi.nullptr) calloc.free(aPtr);
      yl_iir_ctx_destroy(ctx);
    }
  }
}
