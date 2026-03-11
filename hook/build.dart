// hook/build.dart
import 'dart:io';

import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:code_assets/code_assets.dart';

const packageName = 'open_dspc';

String? cppStdLibForOs(OS os) {
  switch (os) {
    case OS.android:
      return 'c++_shared';
    case OS.iOS:
    case OS.macOS:
      return 'c++';
    case OS.linux:
      return 'stdc++';
    default:
      return null;
  }
}

void main(List<String> args) async {
  // Enable hierarchical logging
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.message}');
    if (record.error != null) print(record.error);
    if (record.stackTrace != null) print(record.stackTrace);
  });

  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final os = input.config.code.targetOS;
    final targetArch = input.config.code.targetArchitecture;

    // Choose sources per platform.
    final sources = <String>[
      'src/dsp/fft.c',
      'src/ffi/fft_ffi.c',
      'src/dsp/lpc.c',
      'src/ffi/lpc_ffi.c',
      'src/dsp/filter.c',
      'src/ffi/filter_ffi.c',
      'src/dsp/peaks.c',
      'src/dsp/conv.c',
      'src/ffi/conv_ffi.c',
      'src/dsp/polyfit.c',
      'src/ffi/polyfit_ffi.c',
      'src/dsp/resample.c',
      'src/ffi/resample_ffi.c',
      'src/dsp/window.c',
      'src/dsp/stft.c',
      'src/feature/pitch.c',
      'src/ffi/pitch_ffi.c',
      'src/feature/mel.c',
      'src/ffi/mel_ffi.c',
    ];

    final includeDirs = <String>[
      'src',
      'include',
      'include/ffi',
      'src/third_party/pffft',
      'src/third_party/kissfft',
      'src/third_party/pocketfft-cpp',
      'src/third_party/pocketfft-c',
    ];

    final defines = <String, String?>{'OPENDSPC_BUILD': '1'};
    final fftBackend = (Platform.environment['OPENDSPC_FFT_BACKEND'] ?? 'auto')
        .toLowerCase();
    print('using FFT backend: $fftBackend');

    // Select one backend implementation because each backend exports the same symbols.
    if (fftBackend == 'auto') {
      defines['OPENDSPC_FFT_BACKEND_AUTO'] = '1';
      sources.addAll([
        'src/backend/fft_backend_auto.c',
        'src/third_party/pffft/pffft.c',
        'src/third_party/pffft/pffft_common.c',
        'src/third_party/pocketfft-c/pocketfft_f32.c',
      ]);
    } else if (fftBackend == 'pocketfft_c') {
      defines['OPENDSPC_FFT_BACKEND_POCKETFFT_C'] = '1';
      sources.addAll([
        'src/backend/fft_backend_pocketfft_c.c',
        'src/third_party/pocketfft-c/pocketfft_f32.c',
      ]);
    } else if (fftBackend == 'pocketfft') {
      defines['OPENDSPC_FFT_BACKEND_POCKETFFT'] = '1';
      sources.addAll(['src/backend/fft_backend_pocketfft.cpp']);
    } else if (fftBackend == 'kissfft') {
      defines['OPENDSPC_FFT_BACKEND_KISSFFT'] = '1';
      sources.addAll([
        'src/backend/fft_backend_kissfft.c',
        'src/third_party/kissfft/kiss_fft.c',
        'src/third_party/kissfft/kiss_fftr.c',
      ]);
    } else if (os == OS.android) {
      defines['OPENDSPC_FFT_BACKEND_PFFFT'] = '1';
      sources.addAll([
        'src/backend/fft_backend_pffft.c',
        'src/third_party/pffft/pffft.c',
        'src/third_party/pffft/pffft_common.c',
      ]);
    } else {
      defines['OPENDSPC_FFT_BACKEND_PFFFT'] = '1';
      sources.addAll([
        'src/backend/fft_backend_pffft.c',
        'src/third_party/pffft/pffft.c',
        'src/third_party/pffft/pffft_common.c',
      ]);
    }

    final isArmTarget =
        targetArch == Architecture.arm || targetArch == Architecture.arm64;
    if (isArmTarget) {
      defines['PFFFT_ENABLE_NEON'] = '1';
    }

    // Optional SIMD/compiler tuning controls for benchmarking/reproducibility.
    // OPENDSPC_SIMD: auto (default), avx2, native, none
    // OPENDSPC_CFLAGS: extra raw compiler flags separated by whitespace
    final flags = <String>[];
    final simdPref = (Platform.environment['OPENDSPC_SIMD'] ?? 'auto')
        .toLowerCase();
    if (simdPref == 'none') {
      defines['PFFFT_SIMD_DISABLE'] = '1';
    } else if (simdPref == 'avx2') {
      if (os == OS.windows) {
        flags.add('/arch:AVX2');
      } else {
        flags.addAll(['-mavx2', '-mfma']);
      }
    } else if (simdPref == 'native') {
      if (os == OS.windows) {
        // MSVC has no direct -march=native equivalent.
        // Keep default ISA unless explicitly requesting avx2.
      } else {
        flags.add('-march=native');
      }
    }

    final extraFlags = Platform.environment['OPENDSPC_CFLAGS'];
    if (extraFlags != null && extraFlags.trim().isNotEmpty) {
      flags.addAll(
        extraFlags.split(RegExp(r'\s+')).where((f) => f.trim().isNotEmpty),
      );
    }

    final libraries = <String>[];
    if (os != OS.windows) {
      libraries.add('m');
    }
    if (fftBackend == 'pocketfft') {
      final cppStdLib = cppStdLibForOs(os);
      if (cppStdLib != null) {
        libraries.add(cppStdLib);
      }
    }

    final builder = CBuilder.library(
      name: 'opendspc', // library base name
      assetName: 'bindings/${packageName}_bindings_generated.dart',
      sources: sources,
      includes: includeDirs,
      defines: defines,
      flags: flags,
      libraries: libraries,
    );

    await builder.run(input: input, output: output, logger: Logger('opendspc'));
  });
}
