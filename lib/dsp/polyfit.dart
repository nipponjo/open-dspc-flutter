import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../bindings/open_dspc_bindings_generated.dart'
    show
        yl_polyfit_ctx_create_f64,
        yl_polyfit_ctx_destroy_f64,
        yl_polyfit_ctx_eval_scaled_f64,
        yl_polyfit_ctx_eval_xdomain_f64,
        yl_polyfit_ctx_fit_f64;
import '../utils/native_handle.dart';

enum CoeffMode {
  scaled(0),
  orig(1);

  const CoeffMode(this.value);
  final int value;
}

final class _PolyfitResource implements NativeResource {
  ffi.Pointer<ffi.Void> ctx;

  _PolyfitResource(this.ctx);

  @override
  void free() {
    yl_polyfit_ctx_destroy_f64(ctx);
  }
}

class Polyfitter extends NativeHandle<_PolyfitResource> {
  final int deg;
  int _nmax;

  Float64List? _coeffs;
  CoeffMode? _coeffMode;

  Polyfitter._(this.deg, this._nmax, _PolyfitResource res) : super(res);

  factory Polyfitter({required int deg, int? nmax}) {
    final initialNmax = nmax ?? (deg + 1);
    final ctx = yl_polyfit_ctx_create_f64(deg, initialNmax);
    if (ctx == ffi.nullptr) {
      throw StateError('Failed to create polyfit context');
    }
    return Polyfitter._(deg, initialNmax, _PolyfitResource(ctx));
  }

  int get nmax => _nmax;

  void _ensureCapacity(int requiredNmax) {
    if (requiredNmax <= _nmax) return;

    final newCtx = yl_polyfit_ctx_create_f64(deg, requiredNmax);
    if (newCtx == ffi.nullptr) {
      throw StateError(
        'Failed to recreate polyfit context with nmax=$requiredNmax',
      );
    }

    yl_polyfit_ctx_destroy_f64(res.ctx);
    res.ctx = newCtx;
    _nmax = requiredNmax;
  }

  Float64List? get coeffs =>
      _coeffs == null ? null : Float64List.fromList(_coeffs!);

  CoeffMode? get coeffMode => _coeffMode;

  /// Fits polynomial coefficients to [x] and [y], stores them in this instance,
  /// and returns the fitted coefficient vector.
  Float64List polyfit(
    Float64List x,
    Float64List y, {
    CoeffMode mode = CoeffMode.scaled,
  }) {
    if (x.length != y.length) {
      throw ArgumentError('x and y must have the same length');
    }

    final n = x.length;
    _ensureCapacity(n);
    ffi.Pointer<ffi.Double> xPtr = ffi.nullptr;
    ffi.Pointer<ffi.Double> yPtr = ffi.nullptr;
    ffi.Pointer<ffi.Double> coeffPtr = ffi.nullptr;

    try {
      xPtr = calloc<ffi.Double>(n);
      yPtr = calloc<ffi.Double>(n);
      coeffPtr = calloc<ffi.Double>(deg + 1);

      xPtr.asTypedList(n).setAll(0, x);
      yPtr.asTypedList(n).setAll(0, y);

      final rc = yl_polyfit_ctx_fit_f64(
        res.ctx,
        xPtr,
        yPtr,
        n,
        mode.value,
        coeffPtr,
        ffi.nullptr,
      );
      if (rc != 0) {
        throw StateError('yl_polyfit_ctx_fit_f64 failed with code $rc');
      }

      final out = Float64List.fromList(coeffPtr.asTypedList(deg + 1));
      _coeffs = out;
      _coeffMode = mode;
      return Float64List.fromList(out);
    } finally {
      if (xPtr != ffi.nullptr) calloc.free(xPtr);
      if (yPtr != ffi.nullptr) calloc.free(yPtr);
      if (coeffPtr != ffi.nullptr) calloc.free(coeffPtr);
    }
  }

  /// Evaluates the coefficients stored by the most recent [polyfit] call.
  ///
  /// If the stored coefficients are scaled-domain coefficients, the native
  /// context's saved scaling is used automatically.
  Float64List polyval(Float64List x) {
    final coeffs = _coeffs;
    final mode = _coeffMode;
    if (coeffs == null || mode == null) {
      throw StateError(
        'No fitted coefficients available. Call polyfit() first.',
      );
    }

    final n = x.length;
    ffi.Pointer<ffi.Double> xPtr = ffi.nullptr;
    ffi.Pointer<ffi.Double> coeffPtr = ffi.nullptr;
    ffi.Pointer<ffi.Double> outPtr = ffi.nullptr;

    try {
      xPtr = calloc<ffi.Double>(n);
      coeffPtr = calloc<ffi.Double>(deg + 1);
      outPtr = calloc<ffi.Double>(n);

      xPtr.asTypedList(n).setAll(0, x);
      coeffPtr.asTypedList(deg + 1).setAll(0, coeffs);

      final rc = mode == CoeffMode.scaled
          ? yl_polyfit_ctx_eval_scaled_f64(res.ctx, xPtr, n, coeffPtr, outPtr)
          : yl_polyfit_ctx_eval_xdomain_f64(res.ctx, xPtr, n, coeffPtr, outPtr);

      if (rc != 0) {
        throw StateError('polyval failed with code $rc');
      }

      return Float64List.fromList(outPtr.asTypedList(n));
    } finally {
      if (xPtr != ffi.nullptr) calloc.free(xPtr);
      if (coeffPtr != ffi.nullptr) calloc.free(coeffPtr);
      if (outPtr != ffi.nullptr) calloc.free(outPtr);
    }
  }

  /// Evaluates a polynomial in the original x-domain using Horner's method.
  ///
  /// [coeffs] must be ordered from constant term to highest degree term.
  static Float64List evaluate(Float64List x, Float64List coeffs) {
    final out = Float64List(x.length);
    for (int i = 0; i < x.length; i++) {
      double acc = 0.0;
      for (int j = coeffs.length - 1; j >= 0; j--) {
        acc = acc * x[i] + coeffs[j];
      }
      out[i] = acc;
    }
    return out;
  }
}
