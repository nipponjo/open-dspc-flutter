import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import '../utils/native_handle.dart';

import '../bindings/open_dspc_bindings_generated.dart'
    show
        yl_fft_plan_r2c_create,
        yl_fft_plan_destroy,
        yl_fft_autocorr,
        yl_pitch_acf_frame;

class _AutocorrRes implements NativeResource {
  final ffi.Pointer<ffi.Void> plan;
  final ffi.Pointer<ffi.Float> input;
  final ffi.Pointer<ffi.Float> xcorr;

  _AutocorrRes(this.plan, this.input, this.xcorr);

  @override
  void free() {
    yl_fft_plan_destroy(plan);
    calloc.free(input);
    calloc.free(xcorr);
  }
}

class Autocorr extends NativeHandle<_AutocorrRes> {
  final int n;
  final int inputLen;

  Autocorr._(this.n, this.inputLen, _AutocorrRes res) : super(res);

  factory Autocorr(int n, int inputLen) {
    final plan = yl_fft_plan_r2c_create(n);
    if (plan == ffi.nullptr) {
      throw StateError('yl_fft_plan_r2c_create($n) returned nullptr');
    }

    ffi.Pointer<ffi.Float>? inPtr, xcorrPtr;
    try {
      inPtr = calloc<ffi.Float>(inputLen);
      xcorrPtr = calloc<ffi.Float>(inputLen);
      return Autocorr._(n, inputLen, _AutocorrRes(plan, inPtr, xcorrPtr));
    } catch (_) {
      if (inPtr != null) calloc.free(inPtr);
      if (xcorrPtr != null) calloc.free(xcorrPtr);
      yl_fft_plan_destroy(plan);
      rethrow;
    }
  }

  Float32List execute(Float32List input) {
    if (input.length != inputLen) {
      throw ArgumentError('input length ${input.length} != inputLen $inputLen');
    }

    final r = res;
    r.input.asTypedList(n).setAll(0, input);
    yl_fft_autocorr(r.plan, r.input, inputLen, r.xcorr, inputLen, 0);

    final xcorr = Float32List.fromList(r.xcorr.asTypedList(inputLen));
    return xcorr;
  }

  double pitch(
    Float32List input, {
    double sample_rate = 16000,
    double fmin = 60,
    double fmax = 600,
  }) {
    if (input.length != inputLen) {
      throw ArgumentError('input length ${input.length} != inputLen $inputLen');
    }

    final r = res;
    r.input.asTypedList(n).setAll(0, input);
    final pitch = yl_pitch_acf_frame(
      r.plan,
      r.input,
      inputLen,
      r.xcorr,
      1,
      sample_rate,
      fmin,
      fmax,
    );

    return pitch;
  }
}
