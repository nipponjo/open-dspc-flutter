import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../bindings/open_dspc_bindings_generated.dart'
    show
        yl_autocorr_direct_ffi,
        yl_autocorr_direct_simd_ffi,
        yl_autocorr_out_len_ffi,
        yl_conv_direct_mode_f32_ffi,
        yl_conv_direct_mode_simd_f32_ffi,
        yl_conv_direct_f32_ffi,
        yl_conv_out_len_mode_ffi,
        yl_conv_out_len_ffi,
        yl_fftconv_ctx_bins,
        yl_fftconv_ctx_create_f32,
        yl_fftconv_ctx_destroy,
        yl_fftconv_ctx_h_max,
        yl_fftconv_ctx_nfft,
        yl_fftconv_ctx_process_f32,
        yl_fftconv_ctx_x_max;
import '../utils/native_handle.dart';

enum ConvMode {
  /// Standard linear convolution.
  ///
  /// Computes:
  /// `y[k] = sum_i x[i] * h[k - i]`.
  convolution(0),

  /// Linear cross-correlation.
  ///
  /// Computes:
  /// `y[k] = sum_i x[i] * h[i - k]`.
  xcorr(1);

  const ConvMode(this.value);
  final int value;
}

enum CorrOutMode {
  /// Full linear result (includes all overlap positions).
  full(0),

  /// Only positions with complete overlap.
  valid(1),

  /// Output length equals first input length, centered w.r.t. full.
  same(2);

  const CorrOutMode(this.value);
  final int value;
}

class Conv {
  const Conv._();

  /// Returns the output length of a convolution or cross-correlation operation.
  ///
  /// [nx] is the input length and [nh] is the filter/kernel length.
  static int outLen(int nx, int nh) => yl_conv_out_len_ffi(nx, nh);

  /// Returns output length for the selected scipy-style [outMode].
  ///
  /// - [CorrOutMode.full]: `nx + nh - 1`
  /// - [CorrOutMode.valid]: `max(nx, nh) - min(nx, nh) + 1`
  /// - [CorrOutMode.same]: `nx`
  static int outLenMode(
    int nx,
    int nh, {
    CorrOutMode outMode = CorrOutMode.full,
  }) => yl_conv_out_len_mode_ffi(nx, nh, outMode.value);

  /// Returns lag indices equivalent to `scipy.signal.correlation_lags`.
  ///
  /// For `correlate(in1, in2, mode=...)`, returned lags align with each output
  /// sample in the chosen [mode].
  ///
  /// Example:
  /// ```dart
  /// final lags = Conv.correlationLags(4, 3, mode: CorrOutMode.full);
  /// // [-2, -1, 0, 1, 2, 3]
  /// ```
  static Int32List correlationLags(
    int in1Len,
    int in2Len, {
    CorrOutMode mode = CorrOutMode.full,
  }) {
    if (in1Len <= 0 || in2Len <= 0) {
      throw ArgumentError('in1Len and in2Len must be > 0');
    }

    switch (mode) {
      case CorrOutMode.full:
        {
          final start = -(in2Len - 1);
          final len = in1Len + in2Len - 1;
          return Int32List.fromList(
            List<int>.generate(len, (i) => start + i, growable: false),
          );
        }
      case CorrOutMode.valid:
        {
          if (in1Len >= in2Len) {
            final len = in1Len - in2Len + 1;
            return Int32List.fromList(
              List<int>.generate(len, (i) => i, growable: false),
            );
          }
          final len = in2Len - in1Len + 1;
          final start = -(in2Len - in1Len);
          return Int32List.fromList(
            List<int>.generate(len, (i) => start + i, growable: false),
          );
        }
      case CorrOutMode.same:
        {
          final len = in1Len;
          final start = -(in2Len ~/ 2);
          return Int32List.fromList(
            List<int>.generate(len, (i) => start + i, growable: false),
          );
        }
    }
  }

  /// Computes convolution or cross-correlation directly for one block of data.
  ///
  /// [mode] selects the operation:
  /// - [ConvMode.convolution]: linear convolution.
  /// - [ConvMode.xcorr]: linear cross-correlation.
  ///
  /// [outMode] selects output support:
  /// - [CorrOutMode.full]: length `nx + nh - 1`.
  /// - [CorrOutMode.valid]: complete-overlap region only.
  /// - [CorrOutMode.same]: length `nx`, centered w.r.t. full.
  ///
  /// [simd] enables SIMD acceleration (SSE/NEON/etc) when available.
  /// SIMD may produce tiny floating-point differences vs scalar due to
  /// accumulation order.
  ///
  /// Example:
  /// ```dart
  /// final x = Float32List.fromList([1, 2, 3]);
  /// final h = Float32List.fromList([1, 1, 1]);
  /// final yFull = Conv.direct(
  ///   x,
  ///   h,
  ///   mode: ConvMode.convolution,
  ///   outMode: CorrOutMode.full,
  /// );
  /// final rSame = Conv.direct(
  ///   x,
  ///   h,
  ///   mode: ConvMode.xcorr,
  ///   outMode: CorrOutMode.same,
  ///   simd: true,
  /// );
  /// ```
  static Float32List direct(
    Float32List x,
    Float32List h, {
    ConvMode mode = ConvMode.convolution,
    CorrOutMode outMode = CorrOutMode.full,
    bool simd = false,
  }) {
    final nx = x.length;
    final nh = h.length;
    final ny = outLenMode(nx, nh, outMode: outMode);

    ffi.Pointer<ffi.Float> xPtr = ffi.nullptr;
    ffi.Pointer<ffi.Float> hPtr = ffi.nullptr;
    ffi.Pointer<ffi.Float> yPtr = ffi.nullptr;

    try {
      xPtr = calloc<ffi.Float>(nx);
      hPtr = calloc<ffi.Float>(nh);
      yPtr = calloc<ffi.Float>(ny);

      xPtr.asTypedList(nx).setAll(0, x);
      hPtr.asTypedList(nh).setAll(0, h);

      final rc = (outMode == CorrOutMode.full && !simd)
          ? yl_conv_direct_f32_ffi(xPtr, nx, hPtr, nh, yPtr, mode.value)
          : simd
          ? yl_conv_direct_mode_simd_f32_ffi(
              xPtr,
              nx,
              hPtr,
              nh,
              yPtr,
              mode.value,
              outMode.value,
            )
          : yl_conv_direct_mode_f32_ffi(
              xPtr,
              nx,
              hPtr,
              nh,
              yPtr,
              mode.value,
              outMode.value,
            );
      if (rc != 0) {
        throw StateError('Conv.direct native call failed with code $rc');
      }

      return Float32List.fromList(yPtr.asTypedList(ny));
    } finally {
      if (xPtr != ffi.nullptr) calloc.free(xPtr);
      if (hPtr != ffi.nullptr) calloc.free(hPtr);
      if (yPtr != ffi.nullptr) calloc.free(yPtr);
    }
  }

  /// Returns the output length for direct autocorrelation in [mode].
  static int autocorrOutLen(int n, {CorrOutMode mode = CorrOutMode.full}) =>
      yl_autocorr_out_len_ffi(n, mode.value);

  /// Direct O(n^2) autocorrelation in scipy-style output [mode].
  ///
  /// [mode] controls output support:
  /// - [CorrOutMode.full]: length `2*n - 1`
  /// - [CorrOutMode.valid]: length `1` for autocorrelation
  /// - [CorrOutMode.same]: length `n`
  ///
  /// Set [simd] to `true` to use the SIMD-accelerated kernel when available.
  ///
  /// Example:
  /// ```dart
  /// final x = Float32List.fromList([1, 2, 3, 4]);
  /// final acf = Conv.autocorrDirect(
  ///   x,
  ///   mode: CorrOutMode.same,
  ///   simd: true,
  /// );
  /// ```
  static Float32List autocorrDirect(
    Float32List x, {
    CorrOutMode mode = CorrOutMode.full,
    bool simd = false,
  }) {
    final n = x.length;
    final ny = autocorrOutLen(n, mode: mode);
    ffi.Pointer<ffi.Float> xPtr = ffi.nullptr;
    ffi.Pointer<ffi.Float> yPtr = ffi.nullptr;

    try {
      xPtr = calloc<ffi.Float>(n);
      yPtr = calloc<ffi.Float>(ny);
      xPtr.asTypedList(n).setAll(0, x);

      final rc = simd
          ? yl_autocorr_direct_simd_ffi(xPtr, n, yPtr, mode.value)
          : yl_autocorr_direct_ffi(xPtr, n, yPtr, mode.value);
      if (rc != 0) {
        throw StateError(
          '${simd ? 'yl_autocorr_direct_simd_ffi' : 'yl_autocorr_direct_ffi'} failed with code $rc',
        );
      }
      return Float32List.fromList(yPtr.asTypedList(ny));
    } finally {
      if (xPtr != ffi.nullptr) calloc.free(xPtr);
      if (yPtr != ffi.nullptr) calloc.free(yPtr);
    }
  }
}

final class _FftConvolverResource implements NativeResource {
  /// Cached native context and reusable scratch buffers for [FftConvolver].
  final ffi.Pointer<ffi.Void> ctx;
  ffi.Pointer<ffi.Float> xPtr;
  ffi.Pointer<ffi.Float> hPtr;
  ffi.Pointer<ffi.Float> yPtr;
  int xCapacity;
  int hCapacity;
  int yCapacity;

  _FftConvolverResource(this.ctx)
    : xPtr = ffi.nullptr,
      hPtr = ffi.nullptr,
      yPtr = ffi.nullptr,
      xCapacity = 0,
      hCapacity = 0,
      yCapacity = 0;

  @override
  void free() {
    if (xPtr != ffi.nullptr) calloc.free(xPtr);
    if (hPtr != ffi.nullptr) calloc.free(hPtr);
    if (yPtr != ffi.nullptr) calloc.free(yPtr);
    yl_fftconv_ctx_destroy(ctx);
  }
}

/// Reusable FFT-based convolution context for repeated calls.
///
/// Use this class when the same `xMax`/`hMax` configuration is reused across
/// many calls; it keeps a single native context and internal buffers.
class FftConvolver extends NativeHandle<_FftConvolverResource> {
  final int xMax;
  final int hMax;
  final int nfft;
  final int bins;

  FftConvolver._(
    _FftConvolverResource res, {
    required this.xMax,
    required this.hMax,
    required this.nfft,
    required this.bins,
  }) : super(res);

  /// Creates a reusable convolver with maximum input lengths [xMax] and [hMax].
  ///
  /// A larger capacity allows processing larger signals without recreation.
  factory FftConvolver({required int xMax, required int hMax}) {
    final ctx = yl_fftconv_ctx_create_f32(xMax, hMax);
    if (ctx == ffi.nullptr) {
      throw StateError('Failed to create fft convolution context');
    }

    return FftConvolver._(
      _FftConvolverResource(ctx),
      xMax: yl_fftconv_ctx_x_max(ctx),
      hMax: yl_fftconv_ctx_h_max(ctx),
      nfft: yl_fftconv_ctx_nfft(ctx),
      bins: yl_fftconv_ctx_bins(ctx),
    );
  }

  /// Returns the output length for an input of size `nx` and kernel size `nh`.
  int outLenFor(int nx, int nh) => Conv.outLen(nx, nh);

  /// Ensures the cached input buffer has at least [length] elements.
  void _ensureXCapacity(int length) {
    final r = res;
    if (length <= r.xCapacity) return;
    if (r.xPtr != ffi.nullptr) calloc.free(r.xPtr);
    r.xPtr = calloc<ffi.Float>(length);
    r.xCapacity = length;
  }

  /// Ensures the cached kernel buffer has at least [length] elements.
  void _ensureHCapacity(int length) {
    final r = res;
    if (length <= r.hCapacity) return;
    if (r.hPtr != ffi.nullptr) calloc.free(r.hPtr);
    r.hPtr = calloc<ffi.Float>(length);
    r.hCapacity = length;
  }

  /// Ensures the cached output buffer has at least [length] elements.
  void _ensureYCapacity(int length) {
    final r = res;
    if (length <= r.yCapacity) return;
    if (r.yPtr != ffi.nullptr) calloc.free(r.yPtr);
    r.yPtr = calloc<ffi.Float>(length);
    r.yCapacity = length;
  }

  /// Computes convolution/cross-correlation and returns a newly allocated output.
  ///
  /// Example:
  /// ```dart
  /// final conv = FftConvolver(xMax: 128, hMax: 64);
  /// final y = conv.process(
  ///   Float32List.fromList([1, 2, 3]),
  ///   Float32List.fromList([1, 1, 1]),
  /// );
  /// conv.close();
  /// ```
  Float32List process(
    Float32List x,
    Float32List h, {
    ConvMode mode = ConvMode.convolution,
  }) {
    final nx = x.length;
    final nh = h.length;
    final ny = outLenFor(nx, nh);
    final r = res;

    if (nx > xMax || nh > hMax) {
      throw ArgumentError(
        'input lengths exceed configured maxima (nx=$nx <= $xMax, nh=$nh <= $hMax)',
      );
    }

    _ensureXCapacity(nx);
    _ensureHCapacity(nh);
    _ensureYCapacity(ny);

    r.xPtr.asTypedList(nx).setAll(0, x);
    r.hPtr.asTypedList(nh).setAll(0, h);

    final rc = yl_fftconv_ctx_process_f32(
      r.ctx,
      r.xPtr,
      nx,
      r.hPtr,
      nh,
      r.yPtr,
      mode.value,
    );
    if (rc != 0) {
      throw StateError('yl_fftconv_ctx_process_f32 failed with code $rc');
    }

    return Float32List.fromList(r.yPtr.asTypedList(ny));
  }

  /// Computes into caller-provided [out] to avoid allocating a fresh output.
  ///
  /// Returns the number of samples written.
  /// [out] must be at least `outLenFor(x.length, h.length)` long.
  int processInto(
    Float32List x,
    Float32List h,
    Float32List out, {
    ConvMode mode = ConvMode.convolution,
  }) {
    final nx = x.length;
    final nh = h.length;
    final ny = outLenFor(nx, nh);
    final r = res;

    if (nx > xMax || nh > hMax) {
      throw ArgumentError(
        'input lengths exceed configured maxima (nx=$nx <= $xMax, nh=$nh <= $hMax)',
      );
    }
    if (out.length < ny) {
      throw ArgumentError('out length ${out.length} < required $ny');
    }

    _ensureXCapacity(nx);
    _ensureHCapacity(nh);
    _ensureYCapacity(ny);

    r.xPtr.asTypedList(nx).setAll(0, x);
    r.hPtr.asTypedList(nh).setAll(0, h);

    final rc = yl_fftconv_ctx_process_f32(
      r.ctx,
      r.xPtr,
      nx,
      r.hPtr,
      nh,
      r.yPtr,
      mode.value,
    );
    if (rc != 0) {
      throw StateError('yl_fftconv_ctx_process_f32 failed with code $rc');
    }

    out.setRange(0, ny, r.yPtr.asTypedList(ny));
    return ny;
  }
}
