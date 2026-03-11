import 'dart:io';
import 'dart:typed_data';

class WavData {
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int audioFormat; // 1=PCM, 3=float, 0xFFFE=extensible (resolved below)
  final int byteRate;
  final int blockAlign;

  /// Samples normalized to [-1, 1], interleaved: [ch0, ch1, ..., chN, ch0, ch1, ...]
  final Float32List samples;

  WavData({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.audioFormat,
    required this.byteRate,
    required this.blockAlign,
    required this.samples,
  });

  int get frameCount => samples.length ~/ channels;
  double get durationSeconds => frameCount / sampleRate;

  /// Returns per-channel arrays (copies).
  List<Float32List> deinterleave() {
    final frames = frameCount;
    final out = List.generate(channels, (_) => Float32List(frames));
    for (int f = 0; f < frames; f++) {
      final base = f * channels;
      for (int c = 0; c < channels; c++) {
        out[c][f] = samples[base + c];
      }
    }
    return out;
  }
}

class WavReader {
  /// Read a WAV from bytes (e.g., network, asset, or file you already loaded).
  static WavData readBytes(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);

    int o = 0;
    String read4CC() {
      if (o + 4 > bd.lengthInBytes) {
        throw FormatException('Unexpected EOF while reading FourCC at $o');
      }
      final s = String.fromCharCodes([
        bd.getUint8(o),
        bd.getUint8(o + 1),
        bd.getUint8(o + 2),
        bd.getUint8(o + 3),
      ]);
      o += 4;
      return s;
    }

    int readU32LE() {
      final v = bd.getUint32(o, Endian.little);
      o += 4;
      return v;
    }

    // int readU16LE() {
    //   final v = bd.getUint16(o, Endian.little);
    //   o += 2;
    //   return v;
    // }

    // ---- RIFF header ----
    final riff = read4CC();
    if (riff != 'RIFF' && riff != 'RIFX') {
      throw FormatException('Not a RIFF WAV file (got $riff)');
    }
    final isLittleEndian = riff == 'RIFF';
    if (!isLittleEndian) {
      // RIFX is big-endian WAV; rare.
      throw UnsupportedError(
        'RIFX (big-endian) WAV not supported in this reader.',
      );
    }

    // final riffSize = readU32LE(); // not strictly needed
    final wave = read4CC();
    if (wave != 'WAVE') {
      throw FormatException('RIFF is not WAVE (got $wave)');
    }

    // ---- Scan chunks ----
    int? fmtOffset, fmtSize;
    int? dataOffset, dataSize;

    // Chunks start at current offset; each: 4cc + u32 size + payload (+ pad to even)
    while (o + 8 <= bd.lengthInBytes) {
      final id = read4CC();
      final size = readU32LE();
      final payloadOffset = o;

      if (id == 'fmt ') {
        fmtOffset = payloadOffset;
        fmtSize = size;
      } else if (id == 'data') {
        dataOffset = payloadOffset;
        dataSize = size;
        // We could break here, but some files put junk after data; fmt must already be found.
        // We'll break only if we already have fmt.
        if (fmtOffset != null) break;
      }

      // Skip payload
      o = payloadOffset + size;
      // Pad byte if size is odd (RIFF chunks are word-aligned)
      if (size.isOdd) o += 1;
    }

    if (fmtOffset == null || fmtSize == null) {
      throw FormatException('Missing fmt chunk');
    }
    if (dataOffset == null || dataSize == null) {
      throw FormatException('Missing data chunk');
    }
    if (fmtOffset + fmtSize > bd.lengthInBytes) {
      throw FormatException('fmt chunk exceeds file length');
    }
    if (dataOffset + dataSize > bd.lengthInBytes) {
      throw FormatException('data chunk exceeds file length');
    }

    // ---- Parse fmt ----
    int p = fmtOffset;

    int getU16(int off) => bd.getUint16(off, Endian.little);
    int getU32(int off) => bd.getUint32(off, Endian.little);

    final wFormatTag = getU16(p);
    p += 2;
    final nChannels = getU16(p);
    p += 2;
    final nSamplesPerSec = getU32(p);
    p += 4;
    final nAvgBytesPerSec = getU32(p);
    p += 4;
    final nBlockAlign = getU16(p);
    p += 2;
    final wBitsPerSample = getU16(p);
    p += 2;

    int resolvedFormat = wFormatTag; // 1 PCM, 3 float, 0xFFFE extensible

    // If fmt is extensible, decode subformat
    if (wFormatTag == 0xFFFE) {
      if (fmtSize < 18) {
        throw FormatException('WAVE_FORMAT_EXTENSIBLE fmt chunk too small');
      }
      final cbSize = getU16(p);
      p += 2;
      if (cbSize < 22 || fmtSize < 18 + cbSize) {
        // Spec says cbSize usually 22 for extensible.
        // Some files can be slightly weird, but we require subformat GUID bytes.
        throw FormatException('Invalid extensible fmt extension size');
      }

      // Skip: validBitsPerSample (2), channelMask (4)
      final validBitsPerSample = getU16(p);
      p += 2;
      final channelMask = getU32(p);
      p += 4;

      // SubFormat GUID (16 bytes). We only need to identify PCM vs IEEE float.
      // GUID layout in WAV is little-endian for first 3 fields.
      final sub0 = bd.getUint32(p, Endian.little);
      p += 4; // Data1
      final sub1 = bd.getUint16(p, Endian.little);
      p += 2; // Data2
      final sub2 = bd.getUint16(p, Endian.little);
      p += 2; // Data3
      // Next 8 bytes are big-endian byte order (as stored)
      final b8 = <int>[];
      for (int i = 0; i < 8; i++) {
        b8.add(bd.getUint8(p + i));
      }
      p += 8;

      // Known subformats:
      // PCM  : {00000001-0000-0010-8000-00AA00389B71}
      // FLOAT: {00000003-0000-0010-8000-00AA00389B71}
      final isKsd =
          (sub1 == 0x0000) &&
          (sub2 == 0x0010) &&
          (b8[0] == 0x80) &&
          (b8[1] == 0x00) &&
          (b8[2] == 0x00) &&
          (b8[3] == 0xAA) &&
          (b8[4] == 0x00) &&
          (b8[5] == 0x38) &&
          (b8[6] == 0x9B) &&
          (b8[7] == 0x71);

      if (!isKsd) {
        throw UnsupportedError('Unsupported extensible subformat GUID');
      }
      if (sub0 == 0x00000001) {
        resolvedFormat = 1; // PCM
      } else if (sub0 == 0x00000003) {
        resolvedFormat = 3; // IEEE float
      } else {
        throw UnsupportedError(
          'Unsupported extensible subformat: 0x${sub0.toRadixString(16)}',
        );
      }

      // Some files use validBitsPerSample < bitsPerSample; keep the container bits
      // for decoding, but you can inspect validBitsPerSample if you want.
      // (We ignore channelMask here; channels count already tells us interleaving.)
      // ignore: unused_local_variable
      final _ = channelMask;
      // ignore: unused_local_variable
      final __ = validBitsPerSample;
    }

    if (nChannels <= 0) throw FormatException('Invalid channels: $nChannels');
    if (nBlockAlign <= 0)
      throw FormatException('Invalid blockAlign: $nBlockAlign');
    if (wBitsPerSample <= 0)
      throw FormatException('Invalid bitsPerSample: $wBitsPerSample');

    // ---- Decode data ----
    final dataBd = bd; // same buffer
    final dataStart = dataOffset;
    final dataBytes = dataSize;

    // Ensure whole frames
    final usableBytes = dataBytes - (dataBytes % nBlockAlign);
    final frames = usableBytes ~/ nBlockAlign;
    final totalSamples = frames * nChannels;
    final out = Float32List(totalSamples);

    int di = dataStart;
    int oi = 0;

    double clamp1(double x) => x < -1.0 ? -1.0 : (x > 1.0 ? 1.0 : x);

    if (resolvedFormat == 1) {
      // PCM integer
      switch (wBitsPerSample) {
        case 8:
          // Unsigned [0..255] with 128 as zero
          for (int i = 0; i < totalSamples; i++) {
            final u = dataBd.getUint8(di);
            di += 1;
            out[oi++] = ((u - 128) / 128.0).toDouble();
          }
          break;

        case 16:
          for (int i = 0; i < totalSamples; i++) {
            final s = dataBd.getInt16(di, Endian.little);
            di += 2;
            out[oi++] = (s / 32768.0).toDouble();
          }
          break;

        case 24:
          for (int i = 0; i < totalSamples; i++) {
            final b0 = dataBd.getUint8(di);
            final b1 = dataBd.getUint8(di + 1);
            final b2 = dataBd.getUint8(di + 2);
            di += 3;

            int v = (b0) | (b1 << 8) | (b2 << 16);
            // sign-extend 24-bit
            if (v & 0x800000 != 0) v |= 0xFF000000;
            out[oi++] = (v / 8388608.0).toDouble(); // 2^23
          }
          break;

        case 32:
          for (int i = 0; i < totalSamples; i++) {
            final s = dataBd.getInt32(di, Endian.little);
            di += 4;
            out[oi++] = (s / 2147483648.0).toDouble(); // 2^31
          }
          break;

        default:
          throw UnsupportedError(
            'Unsupported PCM bitsPerSample: $wBitsPerSample',
          );
      }
    } else if (resolvedFormat == 3) {
      // IEEE float
      if (wBitsPerSample != 32) {
        throw UnsupportedError(
          'Unsupported float bitsPerSample: $wBitsPerSample (expected 32)',
        );
      }
      for (int i = 0; i < totalSamples; i++) {
        final f = dataBd.getFloat32(di, Endian.little);
        di += 4;
        out[oi++] = clamp1(f).toDouble();
      }
    } else {
      throw UnsupportedError(
        'Unsupported audio format: 0x${resolvedFormat.toRadixString(16)}',
      );
    }

    return WavData(
      sampleRate: nSamplesPerSec,
      channels: nChannels,
      bitsPerSample: wBitsPerSample,
      audioFormat: resolvedFormat,
      byteRate: nAvgBytesPerSec,
      blockAlign: nBlockAlign,
      samples: out,
    );
  }

  /// Convenience: read from a file path.
  static Future<WavData> readFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return readBytes(bytes);
  }
}
// final wav = await WavReader.readFile('assets/test.wav');
// print('sr=${wav.sampleRate}, ch=${wav.channels}, frames=${wav.frameCount}, dur=${wav.durationSeconds}s');

// final mono = wav.channels == 1
//     ? wav.samples
//     : wav.deinterleave()[0]; // left channel

class WavWriter {
  /// Encode normalized [-1,1] float samples (interleaved) into a WAV byte buffer.
  ///
  /// [samples] are interleaved: [ch0, ch1, ..., chN, ch0, ch1, ...]
  /// [channels] must divide samples.length.
  ///
  /// By default writes 16-bit PCM. You can choose:
  /// - PCM: format=1, bitsPerSample in {8,16,24,32}
  /// - Float: format=3, bitsPerSample must be 32
  static Uint8List encodeBytes(
    Float32List samples, {
    required int sampleRate,
    required int channels,
    int audioFormat = 1, // 1 PCM, 3 IEEE float
    int bitsPerSample = 16,
  }) {
    if (channels <= 0) throw ArgumentError.value(channels, 'channels');
    if (sampleRate <= 0) throw ArgumentError.value(sampleRate, 'sampleRate');
    if (samples.length % channels != 0) {
      throw ArgumentError(
        'samples.length (${samples.length}) must be a multiple of channels ($channels)',
      );
    }

    if (audioFormat == 1) {
      if (bitsPerSample != 8 &&
          bitsPerSample != 16 &&
          bitsPerSample != 24 &&
          bitsPerSample != 32) {
        throw ArgumentError('PCM bitsPerSample must be 8/16/24/32');
      }
    } else if (audioFormat == 3) {
      if (bitsPerSample != 32) {
        throw ArgumentError('Float WAV requires bitsPerSample=32');
      }
    } else {
      throw ArgumentError('audioFormat must be 1 (PCM) or 3 (float)');
    }

    final frames = samples.length ~/ channels;
    final blockAlign = (channels * bitsPerSample) ~/ 8;
    final byteRate = sampleRate * blockAlign;

    // data chunk size in bytes
    final dataSize = frames * blockAlign;

    // Minimal fmt chunk is 16 bytes for PCM/float (no extensible)
    const fmtChunkSize = 16;

    // RIFF size = 4 ("WAVE") + (8 + fmt) + (8 + data)
    final riffSize = 4 + (8 + fmtChunkSize) + (8 + dataSize);

    // Total file bytes = 8 ("RIFF"+size) + riffSize
    final totalSize = 8 + riffSize;

    final out = BytesBuilder(copy: false);

    void writeAscii4(String s) {
      if (s.length != 4) throw ArgumentError('FourCC must be 4 chars');
      out.add(Uint8List.fromList(s.codeUnits));
    }

    void writeU16LE(int v) {
      final b = ByteData(2)..setUint16(0, v, Endian.little);
      out.add(b.buffer.asUint8List());
    }

    void writeU32LE(int v) {
      final b = ByteData(4)..setUint32(0, v, Endian.little);
      out.add(b.buffer.asUint8List());
    }

    // ---- Header ----
    writeAscii4('RIFF');
    writeU32LE(riffSize);
    writeAscii4('WAVE');

    // ---- fmt chunk ----
    writeAscii4('fmt ');
    writeU32LE(fmtChunkSize);
    writeU16LE(audioFormat);
    writeU16LE(channels);
    writeU32LE(sampleRate);
    writeU32LE(byteRate);
    writeU16LE(blockAlign);
    writeU16LE(bitsPerSample);

    // ---- data chunk ----
    writeAscii4('data');
    writeU32LE(dataSize);

    // ---- Samples ----
    // Clamp to [-1,1] before conversion
    double clamp(double x) => x < -1.0 ? -1.0 : (x > 1.0 ? 1.0 : x);

    if (audioFormat == 3) {
      // 32-bit float
      final b = ByteData(dataSize);
      int o = 0;
      for (int i = 0; i < samples.length; i++) {
        final v = clamp(samples[i]).toDouble();
        b.setFloat32(o, v, Endian.little);
        o += 4;
      }
      out.add(b.buffer.asUint8List());
    } else {
      // PCM integer
      switch (bitsPerSample) {
        case 8:
          // unsigned 8-bit: 128 is zero
          final b = Uint8List(dataSize);
          for (int i = 0; i < samples.length; i++) {
            final v = clamp(samples[i]).toDouble();
            final u = (v * 128.0 + 128.0).round();
            b[i] = u.clamp(0, 255);
          }
          out.add(b);
          break;

        case 16:
          final b = ByteData(dataSize);
          int o = 0;
          for (int i = 0; i < samples.length; i++) {
            final v = clamp(samples[i]).toDouble();
            // scale to [-32768, 32767]
            int s = (v * 32768.0).round();
            s = s.clamp(-32768, 32767);
            b.setInt16(o, s, Endian.little);
            o += 2;
          }
          out.add(b.buffer.asUint8List());
          break;

        case 24:
          // 24-bit signed little-endian
          final b = Uint8List(dataSize);
          int o = 0;
          for (int i = 0; i < samples.length; i++) {
            final v = clamp(samples[i]).toDouble();
            int s = (v * 8388608.0).round(); // 2^23
            s = s.clamp(-8388608, 8388607);
            // Two's complement in 24 bits
            final u = s & 0xFFFFFF;
            b[o++] = (u & 0xFF);
            b[o++] = ((u >> 8) & 0xFF);
            b[o++] = ((u >> 16) & 0xFF);
          }
          out.add(b);
          break;

        case 32:
          final b = ByteData(dataSize);
          int o = 0;
          for (int i = 0; i < samples.length; i++) {
            final v = clamp(samples[i]).toDouble();
            int s = (v * 2147483648.0).round(); // 2^31
            s = s.clamp(-2147483648, 2147483647);
            b.setInt32(o, s, Endian.little);
            o += 4;
          }
          out.add(b.buffer.asUint8List());
          break;
      }
    }

    // Chunks are already even-sized here (fmt=16, data depends on align),
    // but RIFF requires word alignment *per chunk*. Since we wrote exact sizes,
    // and blockAlign guarantees dataSize is multiple of (bits/8*channels),
    // it can still be odd in PCM 8-bit mono (blockAlign=1). In that case, pad.
    if (dataSize.isOdd) {
      out.add(Uint8List(1)); // pad byte, NOT counted in chunk size
    }

    final bytes = out.toBytes();
    // Sanity check: total size might be +1 if padded
    if (bytes.length != totalSize && bytes.length != totalSize + 1) {
      // Don’t throw; just keep it as debug help.
      // ignore: avoid_print
      print(
        'WavWriter: size mismatch expected $totalSize(+pad) got ${bytes.length}',
      );
    }
    return bytes;
  }

  /// Convenience: write to a file.
  static Future<void> writeFile(
    String path,
    Float32List samples, {
    required int sampleRate,
    required int channels,
    int audioFormat = 1,
    int bitsPerSample = 16,
  }) async {
    final bytes = encodeBytes(
      samples,
      sampleRate: sampleRate,
      channels: channels,
      audioFormat: audioFormat,
      bitsPerSample: bitsPerSample,
    );
    await File(path).writeAsBytes(bytes, flush: true);
  }
}
// // wav: WavData from your reader
// await WavWriter.writeFile(
//   'out.wav',
//   wav.samples,
//   sampleRate: wav.sampleRate,
//   channels: wav.channels,
//   audioFormat: 1,
//   bitsPerSample: 16,
// );

// // Or write float WAV
// final bytes = WavWriter.encodeBytes(
//   wav.samples,
//   sampleRate: wav.sampleRate,
//   channels: wav.channels,
//   audioFormat: 3,
//   bitsPerSample: 32,
// );
