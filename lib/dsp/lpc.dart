import 'dart:typed_data';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

import '../bindings/open_dspc_bindings_generated.dart'
    show yl_lpc_ctx_create, yl_lpc_ctx_destroy, yl_lpc_ctx_process_frame;

enum LpcMethod {
  /// Autocorrelation + Levinson-Durbin recursion (Yule-Walker LPC).
  levinson,

  /// Burg / Marple-style recursion using forward/backward prediction errors.
  burg,
}

class Lpc {
  const Lpc._();

  /// Estimates LPC denominator coefficients `a[0..order]` from one frame.
  ///
  /// The returned vector has length `order + 1` and follows the convention
  /// `a[0] = 1`.
  ///
  /// Methods:
  /// - [LpcMethod.levinson]: autocorrelation + Levinson-Durbin.
  /// - [LpcMethod.burg]: Burg's method (Marple-style recursion), aligned
  ///   with `librosa.lpc` behavior for real-valued 1-D frames.
  static Float32List lpc(
    Float32List input, {
    required int order,
    LpcMethod method = LpcMethod.levinson,
  }) {
    final L = input.length;
    final ctx = yl_lpc_ctx_create(order);
    if (ctx == ffi.nullptr) {
      throw StateError("Failed to create LPC context");
    }
    ffi.Pointer<ffi.Float> inPtr = ffi.nullptr;
    ffi.Pointer<ffi.Float> outPtr = ffi.nullptr;
    try {
      inPtr = calloc<ffi.Float>(L);
      outPtr = calloc<ffi.Float>(order + 1);
      inPtr.asTypedList(L).setAll(0, input);
      yl_lpc_ctx_process_frame(
        ctx,
        inPtr,
        L,
        method == LpcMethod.burg ? 1 : 0,
        0,
        outPtr,
      );

      final out = Float32List(order + 1);
      out.setAll(0, outPtr.asTypedList(order + 1));
      return out;
    } finally {
      if (inPtr != ffi.nullptr) calloc.free(inPtr);
      if (outPtr != ffi.nullptr) calloc.free(outPtr);
      yl_lpc_ctx_destroy(ctx);
    }
  }
}
