import 'dart:typed_data';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

import '../bindings/open_dspc_bindings_generated.dart'
    show
        yl_mel_ctx_create,
        yl_rfft_bins,
        yl_fft_plan_r2c_create,
        yl_fft_plan_execute_r2c_spec,
        yl_mel_ctx_apply,
        yl_fft_plan_destroy,
        yl_mel_ctx_destroy;

enum MelScale {
  htk(1),
  slaney(2);

  const MelScale(this.value);
  final int value;
}

enum MelNorm {
  none(0),
  slaney(1);

  const MelNorm(this.value);
  final int value;
}

Float32List frameToMel(
  Float32List input, {
  required int sr,
  int numMels = 80,
  double fmin = 0,
  double? fmax,
  MelScale scale = MelScale.htk,
  MelNorm norm = MelNorm.none,
}) {
  final L = input.length;
  final fftCtx = yl_fft_plan_r2c_create(L);
  final bins = yl_rfft_bins(L);
  if (fftCtx == ffi.nullptr) {
    throw StateError("Failed to create FFT context");
  }
  final melCtx = yl_mel_ctx_create(
    sr,
    L,
    numMels,
    fmin,
    fmax ?? (sr / 2),
    scale.value,
    norm.value,
  );
  if (melCtx == ffi.nullptr) {
    throw StateError("Failed to create mel context");
  }
  ffi.Pointer<ffi.Float> inPtr = ffi.nullptr;
  ffi.Pointer<ffi.Float> binsPtr = ffi.nullptr;
  ffi.Pointer<ffi.Float> melPtr = ffi.nullptr;
  try {
    inPtr = calloc<ffi.Float>(L);
    binsPtr = calloc<ffi.Float>(bins);
    melPtr = calloc<ffi.Float>(numMels);
    inPtr.asTypedList(L).setAll(0, input);
    // mode = 2 for power bins
    yl_fft_plan_execute_r2c_spec(fftCtx, inPtr, binsPtr, 2, -120);
    yl_mel_ctx_apply(melCtx, binsPtr, melPtr);

    final out = Float32List(numMels);
    out.setAll(0, melPtr.asTypedList(numMels));
    return out;
  } finally {
    if (inPtr != ffi.nullptr) calloc.free(inPtr);
    if (binsPtr != ffi.nullptr) calloc.free(binsPtr);
    if (melPtr != ffi.nullptr) calloc.free(melPtr);
    yl_mel_ctx_destroy(melCtx);
    yl_fft_plan_destroy(fftCtx);
  }
}
