import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../bindings/stft_bindings.dart'
    show
        yl_stft_bins,
        yl_stft_cfg,
        yl_stft_create,
        yl_stft_destroy,
        yl_stft_flush_r2c,
        yl_stft_flush_spec,
        yl_stft_handle,
        yl_stft_hop,
        yl_stft_nfft,
        yl_stft_process_r2c,
        yl_stft_process_spec,
        yl_stft_push_r2c,
        yl_stft_push_spec,
        yl_stft_reset,
        yl_stft_win_len;
import '../utils/native_handle.dart';
import '../utils/types.dart';
import 'fft.dart' show SpecMode;

/// Window shape applied to each STFT frame before the FFT.
enum StftWindow {
  rect(0),
  hann(1),
  hamming(2),
  blackman(3);

  const StftWindow(this.value);
  final int value;
}

/// Complex STFT output stored as contiguous frame-major real and imaginary bins.
class STFTFrames {
  final int frames;
  final int bins;
  final Float32List real;
  final Float32List imag;

  const STFTFrames._(this.frames, this.bins, this.real, this.imag);

  /// Builds a complex STFT result from caller-owned real and imaginary buffers.
  factory STFTFrames.fromBuffers({
    required int frames,
    required int bins,
    required Float32List real,
    required Float32List imag,
  }) {
    final expectedLen = frames * bins;
    if (real.length != expectedLen || imag.length != expectedLen) {
      throw ArgumentError(
        'real/imag must both have length frames * bins ($expectedLen)',
      );
    }
    return STFTFrames._(frames, bins, real, imag);
  }

  /// Returns an empty complex STFT result with the given bin count.
  factory STFTFrames.empty(int bins) {
    return STFTFrames._(0, bins, Float32List(0), Float32List(0));
  }

  /// Whether this result contains zero frames.
  bool get isEmpty => frames == 0;

  /// Wraps the flattened real and imaginary buffers as a complex vector view.
  Complex32List asComplex() => Complex32List.wrap(real, imag);

  /// Returns the real bins for a single frame as a zero-copy sublist view.
  Float32List frameReal(int index) {
    if (index < 0 || index >= frames) {
      throw RangeError.index(index, real, 'index', null, frames);
    }
    final start = index * bins;
    return Float32List.sublistView(real, start, start + bins);
  }

  /// Returns the imaginary bins for a single frame as a zero-copy sublist view.
  Float32List frameImag(int index) {
    if (index < 0 || index >= frames) {
      throw RangeError.index(index, imag, 'index', null, frames);
    }
    final start = index * bins;
    return Float32List.sublistView(imag, start, start + bins);
  }
}

/// Scalar STFT output stored as contiguous frame-major bins.
class STFTSpecFrames {
  final int frames;
  final int bins;
  final Float32List values;

  const STFTSpecFrames._(this.frames, this.bins, this.values);

  /// Builds a scalar STFT result from a caller-owned frame-major buffer.
  factory STFTSpecFrames.fromBuffer({
    required int frames,
    required int bins,
    required Float32List values,
  }) {
    final expectedLen = frames * bins;
    if (values.length != expectedLen) {
      throw ArgumentError(
        'values must have length frames * bins ($expectedLen)',
      );
    }
    return STFTSpecFrames._(frames, bins, values);
  }

  /// Returns an empty scalar STFT result with the given bin count.
  factory STFTSpecFrames.empty(int bins) {
    return STFTSpecFrames._(0, bins, Float32List(0));
  }

  /// Whether this result contains zero frames.
  bool get isEmpty => frames == 0;

  /// Returns one scalar spectrum frame as a zero-copy sublist view.
  Float32List frame(int index) {
    if (index < 0 || index >= frames) {
      throw RangeError.index(index, values, 'index', null, frames);
    }
    final start = index * bins;
    return Float32List.sublistView(values, start, start + bins);
  }
}

final class _StftResource implements NativeResource {
  final yl_stft_handle handle;

  _StftResource(this.handle);

  /// Releases the native STFT context and its internal scratch buffers.
  @override
  void free() {
    yl_stft_destroy(handle);
  }
}

class STFT extends NativeHandle<_StftResource> {
  final int nFft;
  final int winLen;
  final int hop;
  final int bins;
  final StftWindow window;
  final bool meanSubtract;
  final bool center;

  STFT._({
    required this.nFft,
    required this.winLen,
    required this.hop,
    required this.bins,
    required this.window,
    required this.meanSubtract,
    required this.center,
    required yl_stft_handle handle,
  }) : super(_StftResource(handle));

  /// Creates a reusable native STFT context.
  ///
  /// The instance can be used in streaming mode via [push] and [flush], or in
  /// whole-buffer mode via [process]. The same context also exposes scalar
  /// spectrum variants through [pushSpec], [flushSpec], and [processSpec].
  factory STFT({
    required int nFft,
    int? winLen,
    required int hop,
    StftWindow window = StftWindow.hann,
    bool meanSubtract = false,
    bool center = false,
  }) {
    final actualWinLen = winLen ?? nFft;
    if (nFft <= 0) {
      throw ArgumentError.value(nFft, 'nFft', 'must be > 0');
    }
    if (actualWinLen <= 0 || actualWinLen > nFft) {
      throw ArgumentError.value(
        actualWinLen,
        'winLen',
        'must be > 0 and <= nFft',
      );
    }
    if (hop <= 0) {
      throw ArgumentError.value(hop, 'hop', 'must be > 0');
    }

    final cfg = calloc<yl_stft_cfg>();
    try {
      cfg.ref
        ..n_fft = nFft
        ..win_len = actualWinLen
        ..hop = hop
        ..win = window.value
        ..mean_subtract = meanSubtract ? 1 : 0
        ..center = center ? 1 : 0;

      final handle = yl_stft_create(cfg);
      if (handle == ffi.nullptr) {
        throw StateError(
          'yl_stft_create(nFft: $nFft, winLen: $actualWinLen, hop: $hop) returned nullptr',
        );
      }

      return STFT._(
        nFft: yl_stft_nfft(handle),
        winLen: yl_stft_win_len(handle),
        hop: yl_stft_hop(handle),
        bins: yl_stft_bins(handle),
        window: window,
        meanSubtract: meanSubtract,
        center: center,
        handle: handle,
      );
    } finally {
      calloc.free(cfg);
    }
  }

  /// Creates an STFT context intended for repeated chunked input.
  factory STFT.streaming({
    required int nFft,
    int? winLen,
    required int hop,
    StftWindow window = StftWindow.hann,
    bool meanSubtract = false,
    bool center = false,
  }) => STFT(
    nFft: nFft,
    winLen: winLen,
    hop: hop,
    window: window,
    meanSubtract: meanSubtract,
    center: center,
  );

  /// Creates an STFT context intended for whole-buffer processing.
  factory STFT.offline({
    required int nFft,
    int? winLen,
    required int hop,
    StftWindow window = StftWindow.hann,
    bool meanSubtract = false,
    bool center = false,
  }) => STFT(
    nFft: nFft,
    winLen: winLen,
    hop: hop,
    window: window,
    meanSubtract: meanSubtract,
    center: center,
  );

  /// Clears the streaming state so the next input starts a fresh analysis run.
  void reset() {
    yl_stft_reset(res.handle);
  }

  /// Maximum number of frames a flush can emit for the current overlap setup.
  int get maxFlushFrames {
    if (hop >= winLen) return 1;
    return (winLen + hop - 1) ~/ hop;
  }

  /// Conservative frame upper bound for one streaming push call.
  int maxPushFrames(int inputLength) {
    if (inputLength <= 0) return 0;
    return ((inputLength + hop - 1) ~/ hop) + 1;
  }

  /// Conservative frame upper bound for [process], including the final flush.
  int maxProcessFrames(int signalLength) {
    if (signalLength <= 0) return 0;
    return maxPushFrames(signalLength) + maxFlushFrames;
  }

  /// Pushes one input chunk and returns any complex STFT frames produced.
  STFTFrames push(Float32List input) {
    if (input.isEmpty) return STFTFrames.empty(bins);
    return _runInputComplexOp(
      input,
      framesCap: maxPushFrames(input.length),
      op: (inputPtr, outRe, outIm, framesCap) {
        return yl_stft_push_r2c(
          res.handle,
          inputPtr,
          input.length,
          outRe,
          outIm,
          framesCap,
        );
      },
    );
  }

  /// Flushes the tail of a streaming run and returns the remaining complex frames.
  STFTFrames flush() {
    return _runOutputOnlyComplexOp(
      framesCap: maxFlushFrames,
      op: (outRe, outIm, framesCap) {
        return yl_stft_flush_r2c(res.handle, outRe, outIm, framesCap);
      },
    );
  }

  /// Processes a whole signal buffer and returns all complex STFT frames.
  STFTFrames process(Float32List signal) {
    if (signal.isEmpty) {
      reset();
      return STFTFrames.empty(bins);
    }
    return _runInputComplexOp(
      signal,
      framesCap: maxProcessFrames(signal.length),
      op: (inputPtr, outRe, outIm, framesCap) {
        return yl_stft_process_r2c(
          res.handle,
          inputPtr,
          signal.length,
          outRe,
          outIm,
          framesCap,
        );
      },
    );
  }

  /// Pushes one input chunk and returns scalar spectrum frames directly.
  ///
  /// This path uses the native FFT spectrum routine, so it can emit magnitude,
  /// power, or dB bins without returning intermediate complex spectra.
  STFTSpecFrames pushSpec(
    Float32List input, {
    SpecMode mode = SpecMode.power,
    double dbFloor = -120.0,
  }) {
    if (input.isEmpty) return STFTSpecFrames.empty(bins);
    return _runInputSpecOp(
      input,
      framesCap: maxPushFrames(input.length),
      mode: mode,
      dbFloor: dbFloor,
      op: (inputPtr, outBins, framesCap, mode, dbFloor) {
        return yl_stft_push_spec(
          res.handle,
          inputPtr,
          input.length,
          outBins,
          framesCap,
          mode.value,
          dbFloor,
        );
      },
    );
  }

  /// Flushes the tail of a streaming run and returns scalar spectrum frames.
  STFTSpecFrames flushSpec({
    SpecMode mode = SpecMode.power,
    double dbFloor = -120.0,
  }) {
    return _runOutputOnlySpecOp(
      framesCap: maxFlushFrames,
      mode: mode,
      dbFloor: dbFloor,
      op: (outBins, framesCap, mode, dbFloor) {
        return yl_stft_flush_spec(
          res.handle,
          outBins,
          framesCap,
          mode.value,
          dbFloor,
        );
      },
    );
  }

  /// Processes a whole signal buffer and returns scalar spectrum frames directly.
  STFTSpecFrames processSpec(
    Float32List signal, {
    SpecMode mode = SpecMode.power,
    double dbFloor = -120.0,
  }) {
    if (signal.isEmpty) {
      reset();
      return STFTSpecFrames.empty(bins);
    }
    return _runInputSpecOp(
      signal,
      framesCap: maxProcessFrames(signal.length),
      mode: mode,
      dbFloor: dbFloor,
      op: (inputPtr, outBins, framesCap, mode, dbFloor) {
        return yl_stft_process_spec(
          res.handle,
          inputPtr,
          signal.length,
          outBins,
          framesCap,
          mode.value,
          dbFloor,
        );
      },
    );
  }

  /// Allocates native input/output buffers for one complex STFT call with input.
  STFTFrames _runInputComplexOp(
    Float32List input, {
    required int framesCap,
    required int Function(
      ffi.Pointer<ffi.Float> inputPtr,
      ffi.Pointer<ffi.Float> outRe,
      ffi.Pointer<ffi.Float> outIm,
      int framesCap,
    )
    op,
  }) {
    ffi.Pointer<ffi.Float> inputPtr = ffi.nullptr;
    ffi.Pointer<ffi.Float> outRePtr = ffi.nullptr;
    ffi.Pointer<ffi.Float> outImPtr = ffi.nullptr;

    try {
      inputPtr = calloc<ffi.Float>(input.length);
      inputPtr.asTypedList(input.length).setAll(0, input);

      final outputLen = framesCap * bins;
      outRePtr = calloc<ffi.Float>(outputLen);
      outImPtr = calloc<ffi.Float>(outputLen);

      final frames = op(inputPtr, outRePtr, outImPtr, framesCap);
      return _copyComplexFrames(frames, outRePtr, outImPtr);
    } finally {
      if (inputPtr != ffi.nullptr) calloc.free(inputPtr);
      if (outRePtr != ffi.nullptr) calloc.free(outRePtr);
      if (outImPtr != ffi.nullptr) calloc.free(outImPtr);
    }
  }

  /// Allocates native output buffers for one complex STFT call without input.
  STFTFrames _runOutputOnlyComplexOp({
    required int framesCap,
    required int Function(
      ffi.Pointer<ffi.Float> outRe,
      ffi.Pointer<ffi.Float> outIm,
      int framesCap,
    )
    op,
  }) {
    ffi.Pointer<ffi.Float> outRePtr = ffi.nullptr;
    ffi.Pointer<ffi.Float> outImPtr = ffi.nullptr;

    try {
      final outputLen = framesCap * bins;
      outRePtr = calloc<ffi.Float>(outputLen);
      outImPtr = calloc<ffi.Float>(outputLen);

      final frames = op(outRePtr, outImPtr, framesCap);
      return _copyComplexFrames(frames, outRePtr, outImPtr);
    } finally {
      if (outRePtr != ffi.nullptr) calloc.free(outRePtr);
      if (outImPtr != ffi.nullptr) calloc.free(outImPtr);
    }
  }

  /// Allocates native input/output buffers for one scalar-spectrum STFT call.
  STFTSpecFrames _runInputSpecOp(
    Float32List input, {
    required int framesCap,
    required SpecMode mode,
    required double dbFloor,
    required int Function(
      ffi.Pointer<ffi.Float> inputPtr,
      ffi.Pointer<ffi.Float> outBins,
      int framesCap,
      SpecMode mode,
      double dbFloor,
    )
    op,
  }) {
    ffi.Pointer<ffi.Float> inputPtr = ffi.nullptr;
    ffi.Pointer<ffi.Float> outBinsPtr = ffi.nullptr;

    try {
      inputPtr = calloc<ffi.Float>(input.length);
      inputPtr.asTypedList(input.length).setAll(0, input);

      final outputLen = framesCap * bins;
      outBinsPtr = calloc<ffi.Float>(outputLen);

      final frames = op(inputPtr, outBinsPtr, framesCap, mode, dbFloor);
      return _copySpecFrames(frames, outBinsPtr);
    } finally {
      if (inputPtr != ffi.nullptr) calloc.free(inputPtr);
      if (outBinsPtr != ffi.nullptr) calloc.free(outBinsPtr);
    }
  }

  /// Allocates native output buffers for one scalar-spectrum flush call.
  STFTSpecFrames _runOutputOnlySpecOp({
    required int framesCap,
    required SpecMode mode,
    required double dbFloor,
    required int Function(
      ffi.Pointer<ffi.Float> outBins,
      int framesCap,
      SpecMode mode,
      double dbFloor,
    )
    op,
  }) {
    ffi.Pointer<ffi.Float> outBinsPtr = ffi.nullptr;

    try {
      final outputLen = framesCap * bins;
      outBinsPtr = calloc<ffi.Float>(outputLen);

      final frames = op(outBinsPtr, framesCap, mode, dbFloor);
      return _copySpecFrames(frames, outBinsPtr);
    } finally {
      if (outBinsPtr != ffi.nullptr) calloc.free(outBinsPtr);
    }
  }

  /// Copies complex frame-major output from native memory into Dart-owned lists.
  STFTFrames _copyComplexFrames(
    int frames,
    ffi.Pointer<ffi.Float> outRePtr,
    ffi.Pointer<ffi.Float> outImPtr,
  ) {
    if (frames <= 0) return STFTFrames.empty(bins);
    final valuesLen = frames * bins;
    return STFTFrames.fromBuffers(
      frames: frames,
      bins: bins,
      real: Float32List.fromList(outRePtr.asTypedList(valuesLen)),
      imag: Float32List.fromList(outImPtr.asTypedList(valuesLen)),
    );
  }

  /// Copies scalar frame-major output from native memory into a Dart-owned list.
  STFTSpecFrames _copySpecFrames(
    int frames,
    ffi.Pointer<ffi.Float> outBinsPtr,
  ) {
    if (frames <= 0) return STFTSpecFrames.empty(bins);
    final valuesLen = frames * bins;
    return STFTSpecFrames.fromBuffer(
      frames: frames,
      bins: bins,
      values: Float32List.fromList(outBinsPtr.asTypedList(valuesLen)),
    );
  }
}
