// ignore_for_file: camel_case_types, non_constant_identifier_names

import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const _assetId = 'package:open_dspc/bindings/open_dspc_bindings_generated.dart';

const int _ylPeakPropsPlateau = 1 << 0;
const int _ylPeakPropsHeight = 1 << 1;
const int _ylPeakPropsThreshold = 1 << 2;
const int _ylPeakPropsProminence = 1 << 3;
const int _ylPeakPropsWidth = 1 << 4;

final class _ylPeakBoundF32 extends ffi.Struct {
  @ffi.Int()
  external int enabled;

  @ffi.Int()
  external int use_array;

  @ffi.Float()
  external double value;

  external ffi.Pointer<ffi.Float> values;
}

final class _ylPeakIntervalF32 extends ffi.Struct {
  external _ylPeakBoundF32 min;
  external _ylPeakBoundF32 max;
}

final class _ylPeakBoundSize extends ffi.Struct {
  @ffi.Int()
  external int enabled;

  @ffi.Int()
  external int use_array;

  @ffi.Size()
  external int value;

  external ffi.Pointer<ffi.Size> values;
}

final class _ylPeakIntervalSize extends ffi.Struct {
  external _ylPeakBoundSize min;
  external _ylPeakBoundSize max;
}

final class _ylFindPeaksOptions extends ffi.Struct {
  external _ylPeakIntervalF32 height;
  external _ylPeakIntervalF32 threshold;

  @ffi.Int()
  external int distance_enabled;

  @ffi.Float()
  external double distance;

  external _ylPeakIntervalF32 prominence;
  external _ylPeakIntervalF32 width;

  @ffi.Int()
  external int wlen_enabled;

  @ffi.Size()
  external int wlen;

  @ffi.Int()
  external int rel_height_enabled;

  @ffi.Float()
  external double rel_height;

  external _ylPeakIntervalSize plateau_size;
}

final class _ylFindPeaksResult extends ffi.Struct {
  @ffi.Size()
  external int count;

  @ffi.Size()
  external int capacity;

  @ffi.Uint32()
  external int properties;

  external ffi.Pointer<ffi.Size> peaks;

  external ffi.Pointer<ffi.Size> plateau_sizes;
  external ffi.Pointer<ffi.Size> left_edges;
  external ffi.Pointer<ffi.Size> right_edges;

  external ffi.Pointer<ffi.Float> peak_heights;

  external ffi.Pointer<ffi.Float> left_thresholds;
  external ffi.Pointer<ffi.Float> right_thresholds;

  external ffi.Pointer<ffi.Float> prominences;
  external ffi.Pointer<ffi.Size> left_bases;
  external ffi.Pointer<ffi.Size> right_bases;

  external ffi.Pointer<ffi.Float> widths;
  external ffi.Pointer<ffi.Float> width_heights;
  external ffi.Pointer<ffi.Float> left_ips;
  external ffi.Pointer<ffi.Float> right_ips;
}

@ffi.Native<
  ffi.Int Function(
    ffi.Pointer<ffi.Float>,
    ffi.Size,
    ffi.Pointer<_ylFindPeaksOptions>,
    ffi.Pointer<_ylFindPeaksResult>,
  )
>(assetId: _assetId, symbol: 'find_peaks')
external int _find_peaks_native(
  ffi.Pointer<ffi.Float> x,
  int xLen,
  ffi.Pointer<_ylFindPeaksOptions> options,
  ffi.Pointer<_ylFindPeaksResult> out,
);

@ffi.Native<ffi.Void Function(ffi.Pointer<_ylFindPeaksResult>)>(
  assetId: _assetId,
  symbol: 'yl_find_peaks_result_free',
)
external void _yl_find_peaks_result_free(
  ffi.Pointer<_ylFindPeaksResult> result,
);

class FindPeaksProperties {
  final Int64List? plateau_sizes;
  final Int64List? left_edges;
  final Int64List? right_edges;
  final Float32List? peak_heights;
  final Float32List? left_thresholds;
  final Float32List? right_thresholds;
  final Float32List? prominences;
  final Int64List? left_bases;
  final Int64List? right_bases;
  final Float32List? widths;
  final Float32List? width_heights;
  final Float32List? left_ips;
  final Float32List? right_ips;

  const FindPeaksProperties({
    this.plateau_sizes,
    this.left_edges,
    this.right_edges,
    this.peak_heights,
    this.left_thresholds,
    this.right_thresholds,
    this.prominences,
    this.left_bases,
    this.right_bases,
    this.widths,
    this.width_heights,
    this.left_ips,
    this.right_ips,
  });
}

class FindPeaksResult {
  final Int64List peaks;
  final FindPeaksProperties properties;

  const FindPeaksResult(this.peaks, this.properties);
}

class _FloatBoundSpec {
  final bool enabled;
  final bool useArray;
  final double scalar;
  final Float32List? array;

  const _FloatBoundSpec.disabled()
    : enabled = false,
      useArray = false,
      scalar = 0,
      array = null;

  const _FloatBoundSpec.scalar(this.scalar)
    : enabled = true,
      useArray = false,
      array = null;

  const _FloatBoundSpec.array(this.array)
    : enabled = true,
      useArray = true,
      scalar = 0;
}

class _FloatIntervalSpec {
  final _FloatBoundSpec min;
  final _FloatBoundSpec max;

  const _FloatIntervalSpec(this.min, this.max);
}

class _SizeBoundSpec {
  final bool enabled;
  final bool useArray;
  final int scalar;
  final Int64List? array;

  const _SizeBoundSpec.disabled()
    : enabled = false,
      useArray = false,
      scalar = 0,
      array = null;

  const _SizeBoundSpec.scalar(this.scalar)
    : enabled = true,
      useArray = false,
      array = null;

  const _SizeBoundSpec.array(this.array)
    : enabled = true,
      useArray = true,
      scalar = 0;
}

class _SizeIntervalSpec {
  final _SizeBoundSpec min;
  final _SizeBoundSpec max;

  const _SizeIntervalSpec(this.min, this.max);
}

class _NativeAllocations {
  final List<ffi.Pointer<ffi.NativeType>> _allocations = [];

  ffi.Pointer<ffi.Float> allocFloatArray(Float32List values) {
    final ptr = calloc<ffi.Float>(values.length);
    ptr.asTypedList(values.length).setAll(0, values);
    _allocations.add(ptr);
    return ptr;
  }

  ffi.Pointer<ffi.Size> allocSizeArray(Int64List values) {
    final ptr = calloc<ffi.Size>(values.length);
    for (var i = 0; i < values.length; i++) {
      (ptr + i).value = values[i];
    }
    _allocations.add(ptr);
    return ptr;
  }

  void freeAll() {
    for (final ptr in _allocations.reversed) {
      calloc.free(ptr);
    }
    _allocations.clear();
  }
}

/// Finds local maxima in a 1-D signal using the native peak finder.
///
/// This mirrors SciPy's `find_peaks` parameter names:
/// `find_peaks(x, height=None, threshold=None, distance=None, prominence=None,
/// width=None, wlen=None, rel_height=0.5, plateau_size=None)`.
///
/// The first argument [x] is the input signal. It may be any `List<num>`, but
/// a [Float32List] avoids an extra conversion.
///
/// Parameter meanings:
/// - [height]: required absolute peak value in `x`
/// - [threshold]: required vertical drop from a peak to its immediate
///   neighbours
/// - [distance]: minimum spacing, in samples, between accepted peak indices
/// - [prominence]: how much a peak stands out from its surrounding baseline
/// - [width]: peak width measured at `peak_height - prominence * rel_height`
/// - [wlen]: optional window length used while computing prominence and width
/// - [rel_height]: relative height used for width measurement; `0.5` means
///   half-prominence width
/// - [plateau_size]: allowed size of a flat-top peak in samples
///
/// Optional conditions accept the same broad shapes as SciPy:
/// - scalar: `height: 0.5`
/// - interval pair: `prominence: (0.2, null)` or `width: [3, 20]`
/// - per-sample array with the same length as [x]:
///   `height: Float32List.fromList(...)`
///
/// Interval semantics are inclusive. `null` means an open bound, so
/// `(0.2, null)` means `>= 0.2` and `(null, 1.0)` means `<= 1.0`.
///
/// Returned [FindPeaksResult]:
/// - [FindPeaksResult.peaks] contains the selected peak indices
/// - [FindPeaksResult.properties] contains any computed properties requested by
///   the active filters, such as `peak_heights`, `prominences`, `widths`, or
///   plateau metadata
///
/// Example: basic use
/// ```dart
/// final result = find_peaks(signal, height: 0.8, distance: 16);
/// print(result.peaks);
/// print(result.properties.peak_heights);
/// ```
///
/// Example: interval constraints
/// ```dart
/// final result = find_peaks(
///   signal,
///   prominence: (0.2, null),
///   width: [2, 12],
///   rel_height: 0.5,
/// );
/// ```
///
/// Example: dynamic per-sample threshold
/// ```dart
/// final floor = Float32List.fromList(List.filled(signal.length, 0.4));
/// final result = find_peaks(signal, height: floor);
/// ```
///
/// Notes:
/// - [distance] must be `>= 1`
/// - array-backed constraints must have the same length as [x]
/// - [wlen] is only used when prominence or width is requested
FindPeaksResult find_peaks(
  List<num> x, {
  Object? height,
  Object? threshold,
  double? distance,
  Object? prominence,
  Object? width,
  int? wlen,
  double rel_height = 0.5,
  Object? plateau_size,
}) {
  final signal = _toFloat32List(x);
  final heightSpec = _parseFloatInterval('height', height, signal.length);
  final thresholdSpec = _parseFloatInterval(
    'threshold',
    threshold,
    signal.length,
  );
  final prominenceSpec = _parseFloatInterval(
    'prominence',
    prominence,
    signal.length,
  );
  final widthSpec = _parseFloatInterval('width', width, signal.length);
  final plateauSpec = _parseSizeInterval(
    'plateau_size',
    plateau_size,
    signal.length,
  );

  final allocs = _NativeAllocations();
  final xPtr = calloc<ffi.Float>(signal.length);
  final optionsPtr = calloc<_ylFindPeaksOptions>();
  final resultPtr = calloc<_ylFindPeaksResult>();

  try {
    xPtr.asTypedList(signal.length).setAll(0, signal);

    final options = optionsPtr.ref;
    _writeFloatInterval(options.height, heightSpec, allocs);
    _writeFloatInterval(options.threshold, thresholdSpec, allocs);
    options.distance_enabled = distance == null ? 0 : 1;
    options.distance = distance ?? 0;
    _writeFloatInterval(options.prominence, prominenceSpec, allocs);
    _writeFloatInterval(options.width, widthSpec, allocs);
    options.wlen_enabled = wlen == null ? 0 : 1;
    options.wlen = wlen ?? 0;
    options.rel_height_enabled = 1;
    options.rel_height = rel_height;
    _writeSizeInterval(options.plateau_size, plateauSpec, allocs);

    final status = _find_peaks_native(
      xPtr,
      signal.length,
      optionsPtr,
      resultPtr,
    );
    if (status != 0) {
      throw StateError(_findPeaksErrorMessage(status));
    }

    final result = resultPtr.ref;
    final count = result.count;
    final peaks = Int64List.fromList(_copySizeValues(result.peaks, count));
    final flags = result.properties;
    final properties = FindPeaksProperties(
      plateau_sizes: _hasFlag(flags, _ylPeakPropsPlateau)
          ? Int64List.fromList(_copySizeValues(result.plateau_sizes, count))
          : null,
      left_edges: _hasFlag(flags, _ylPeakPropsPlateau)
          ? Int64List.fromList(_copySizeValues(result.left_edges, count))
          : null,
      right_edges: _hasFlag(flags, _ylPeakPropsPlateau)
          ? Int64List.fromList(_copySizeValues(result.right_edges, count))
          : null,
      peak_heights: _hasFlag(flags, _ylPeakPropsHeight)
          ? Float32List.fromList(_copyFloatValues(result.peak_heights, count))
          : null,
      left_thresholds: _hasFlag(flags, _ylPeakPropsThreshold)
          ? Float32List.fromList(
              _copyFloatValues(result.left_thresholds, count),
            )
          : null,
      right_thresholds: _hasFlag(flags, _ylPeakPropsThreshold)
          ? Float32List.fromList(
              _copyFloatValues(result.right_thresholds, count),
            )
          : null,
      prominences: _hasFlag(flags, _ylPeakPropsProminence)
          ? Float32List.fromList(_copyFloatValues(result.prominences, count))
          : null,
      left_bases: _hasFlag(flags, _ylPeakPropsProminence)
          ? Int64List.fromList(_copySizeValues(result.left_bases, count))
          : null,
      right_bases: _hasFlag(flags, _ylPeakPropsProminence)
          ? Int64List.fromList(_copySizeValues(result.right_bases, count))
          : null,
      widths: _hasFlag(flags, _ylPeakPropsWidth)
          ? Float32List.fromList(_copyFloatValues(result.widths, count))
          : null,
      width_heights: _hasFlag(flags, _ylPeakPropsWidth)
          ? Float32List.fromList(_copyFloatValues(result.width_heights, count))
          : null,
      left_ips: _hasFlag(flags, _ylPeakPropsWidth)
          ? Float32List.fromList(_copyFloatValues(result.left_ips, count))
          : null,
      right_ips: _hasFlag(flags, _ylPeakPropsWidth)
          ? Float32List.fromList(_copyFloatValues(result.right_ips, count))
          : null,
    );

    return FindPeaksResult(peaks, properties);
  } finally {
    _yl_find_peaks_result_free(resultPtr);
    calloc.free(resultPtr);
    calloc.free(optionsPtr);
    calloc.free(xPtr);
    allocs.freeAll();
  }
}

Float32List _toFloat32List(List<num> values) {
  if (values is Float32List) return values;
  return Float32List.fromList(values.map((v) => v.toDouble()).toList());
}

bool _hasFlag(int flags, int flag) => (flags & flag) != 0;

List<int> _copySizeValues(ffi.Pointer<ffi.Size> ptr, int count) {
  return List<int>.generate(count, (i) => (ptr + i).value);
}

List<double> _copyFloatValues(ffi.Pointer<ffi.Float> ptr, int count) {
  return List<double>.generate(count, (i) => (ptr + i).value);
}

void _writeFloatInterval(
  _ylPeakIntervalF32 target,
  _FloatIntervalSpec spec,
  _NativeAllocations allocs,
) {
  _writeFloatBound(target.min, spec.min, allocs);
  _writeFloatBound(target.max, spec.max, allocs);
}

void _writeFloatBound(
  _ylPeakBoundF32 target,
  _FloatBoundSpec spec,
  _NativeAllocations allocs,
) {
  target.enabled = spec.enabled ? 1 : 0;
  target.use_array = spec.useArray ? 1 : 0;
  target.value = spec.scalar;
  target.values = spec.array == null
      ? ffi.nullptr
      : allocs.allocFloatArray(spec.array!);
}

void _writeSizeInterval(
  _ylPeakIntervalSize target,
  _SizeIntervalSpec spec,
  _NativeAllocations allocs,
) {
  _writeSizeBound(target.min, spec.min, allocs);
  _writeSizeBound(target.max, spec.max, allocs);
}

void _writeSizeBound(
  _ylPeakBoundSize target,
  _SizeBoundSpec spec,
  _NativeAllocations allocs,
) {
  target.enabled = spec.enabled ? 1 : 0;
  target.use_array = spec.useArray ? 1 : 0;
  target.value = spec.scalar;
  target.values = spec.array == null
      ? ffi.nullptr
      : allocs.allocSizeArray(spec.array!);
}

_FloatIntervalSpec _parseFloatInterval(String name, Object? value, int xLen) {
  if (value == null) {
    return const _FloatIntervalSpec(
      _FloatBoundSpec.disabled(),
      _FloatBoundSpec.disabled(),
    );
  }

  final pair = _tryReadIntervalPair(value);
  if (pair != null) {
    return _FloatIntervalSpec(
      _parseFloatBound('$name.min', pair.$1, xLen),
      _parseFloatBound('$name.max', pair.$2, xLen),
    );
  }

  return _FloatIntervalSpec(
    _parseFloatBound(name, value, xLen),
    const _FloatBoundSpec.disabled(),
  );
}

_SizeIntervalSpec _parseSizeInterval(String name, Object? value, int xLen) {
  if (value == null) {
    return const _SizeIntervalSpec(
      _SizeBoundSpec.disabled(),
      _SizeBoundSpec.disabled(),
    );
  }

  final pair = _tryReadIntervalPair(value);
  if (pair != null) {
    return _SizeIntervalSpec(
      _parseSizeBound('$name.min', pair.$1, xLen),
      _parseSizeBound('$name.max', pair.$2, xLen),
    );
  }

  return _SizeIntervalSpec(
    _parseSizeBound(name, value, xLen),
    const _SizeBoundSpec.disabled(),
  );
}

(Object?, Object?)? _tryReadIntervalPair(Object value) {
  if (value is (Object?, Object?)) {
    return value;
  }
  if (value is List && value is! TypedData && value.length == 2) {
    return (value[0], value[1]);
  }
  return null;
}

_FloatBoundSpec _parseFloatBound(String name, Object? value, int xLen) {
  if (value == null) return const _FloatBoundSpec.disabled();
  if (value is num) return _FloatBoundSpec.scalar(value.toDouble());
  if (value is Float32List) {
    _checkLength(name, value.length, xLen);
    return _FloatBoundSpec.array(value);
  }
  if (value is Float64List) {
    _checkLength(name, value.length, xLen);
    return _FloatBoundSpec.array(
      Float32List.fromList(value.map((v) => v.toDouble()).toList()),
    );
  }
  if (value is List<num>) {
    _checkLength(name, value.length, xLen);
    return _FloatBoundSpec.array(
      Float32List.fromList(value.map((v) => v.toDouble()).toList()),
    );
  }
  throw ArgumentError(
    '$name must be a number, an x-shaped array, or a 2-item interval',
  );
}

_SizeBoundSpec _parseSizeBound(String name, Object? value, int xLen) {
  if (value == null) return const _SizeBoundSpec.disabled();
  if (value is int) return _SizeBoundSpec.scalar(value);
  if (value is Int64List) {
    _checkLength(name, value.length, xLen);
    return _SizeBoundSpec.array(value);
  }
  if (value is Int32List) {
    _checkLength(name, value.length, xLen);
    return _SizeBoundSpec.array(Int64List.fromList(value));
  }
  if (value is Uint32List) {
    _checkLength(name, value.length, xLen);
    return _SizeBoundSpec.array(Int64List.fromList(value));
  }
  if (value is List<int>) {
    _checkLength(name, value.length, xLen);
    return _SizeBoundSpec.array(Int64List.fromList(value));
  }
  throw ArgumentError(
    '$name must be an int, an x-shaped integer array, or a 2-item interval',
  );
}

void _checkLength(String name, int actual, int expected) {
  if (actual != expected) {
    throw ArgumentError(
      '$name length must match x length ($expected), got $actual',
    );
  }
}

String _findPeaksErrorMessage(int code) {
  switch (code) {
    case 1:
      return 'find_peaks received invalid arguments';
    case 2:
      return 'find_peaks failed to allocate native memory';
    case 3:
      return '`distance` must be greater than or equal to 1';
    case 4:
      return '`rel_height` must be greater than or equal to 0';
    case 5:
      return 'an array-backed condition was invalid';
    default:
      return 'find_peaks failed with native status $code';
  }
}
