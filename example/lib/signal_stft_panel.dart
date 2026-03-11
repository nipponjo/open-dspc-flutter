import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_dspc/dsp/fft.dart';
import 'package:open_dspc/dsp/stft.dart';
import 'package:open_dspc/io/wave.dart';
import 'package:open_dspc/utils/signal_generator.dart';
import 'package:open_dspc_example/plots/imshow.dart';
import 'package:open_dspc_example/plots/plot_widget.dart';
import 'package:path_provider/path_provider.dart';

enum _SignalKind { sine, cosine, sawtooth, pulseTrain, whiteNoise }

class SignalStftPanel extends StatefulWidget {
  const SignalStftPanel({super.key});

  @override
  State<SignalStftPanel> createState() => _SignalStftPanelState();
}

class _SignalStftPanelState extends State<SignalStftPanel> {
  final _sampleRateCtrl = TextEditingController(text: '16000');
  final _frequencyCtrl = TextEditingController(text: '440');
  final _durationCtrl = TextEditingController(text: '2.0');
  final _amplitudeCtrl = TextEditingController(text: '0.8');
  final _player = AudioPlayer();

  _SignalKind _kind = _SignalKind.sine;
  Float32List _signal = Float32List(0);
  ui.Image? _stftImage;
  String _status = 'Set parameters and press Generate';
  bool _isPlaying = false;

  @override
  void dispose() {
    _sampleRateCtrl.dispose();
    _frequencyCtrl.dispose();
    _durationCtrl.dispose();
    _amplitudeCtrl.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final sampleRate = int.tryParse(_sampleRateCtrl.text.trim());
    final frequency = double.tryParse(_frequencyCtrl.text.trim());
    final durationSec = double.tryParse(_durationCtrl.text.trim());
    final amplitude = double.tryParse(_amplitudeCtrl.text.trim());

    if (sampleRate == null || sampleRate <= 0) {
      setState(() => _status = 'Invalid sample rate');
      return;
    }
    if (durationSec == null || durationSec <= 0) {
      setState(() => _status = 'Invalid duration');
      return;
    }
    if (amplitude == null || amplitude <= 0 || amplitude > 1.0) {
      setState(() => _status = 'Amplitude must be in (0, 1]');
      return;
    }
    if (_kind != _SignalKind.whiteNoise &&
        (frequency == null || frequency <= 0 || frequency >= sampleRate / 2)) {
      setState(
        () => _status =
            'Frequency must be > 0 and < Nyquist (${(sampleRate / 2).toStringAsFixed(0)} Hz)',
      );
      return;
    }

    final n = math.max(1, (sampleRate * durationSec).round());
    final freq = frequency ?? 440.0;

    final signal = switch (_kind) {
      _SignalKind.sine => SignalGenerator.sine(
        n: n,
        freqHz: freq,
        sampleRate: sampleRate.toDouble(),
        amplitude: amplitude,
      ),
      _SignalKind.cosine => SignalGenerator.cosine(
        n: n,
        freqHz: freq,
        sampleRate: sampleRate.toDouble(),
        amplitude: amplitude,
      ),
      _SignalKind.sawtooth => SignalGenerator.sawtooth(
        n: n,
        freqHz: freq,
        sampleRate: sampleRate.toDouble(),
        amplitude: amplitude,
      ),
      _SignalKind.pulseTrain => SignalGenerator.pulseTrain(
        n: n,
        freqHz: freq,
        sampleRate: sampleRate.toDouble(),
        amplitude: amplitude,
      ),
      _SignalKind.whiteNoise => SignalGenerator.whiteNoise(
        n,
        amplitude: amplitude,
      ),
    };

    final nFft = _nextPow2(math.min(2048, math.max(256, sampleRate ~/ 16)));
    final hop = math.max(1, nFft ~/ 4);
    final stft = STFT.offline(
      nFft: nFft,
      winLen: nFft,
      hop: hop,
      window: StftWindow.hann,
    );

    try {
      final spec = stft.processSpec(signal, mode: SpecMode.db, dbFloor: -120.0);
      if (spec.frames == 0) {
        setState(() {
          _signal = signal;
          _stftImage = null;
          _status = 'Generated signal, but STFT produced zero frames';
        });
        return;
      }

      final frames = List<Float32List>.generate(
        spec.frames,
        (i) => spec.frame(i),
        growable: false,
      );
      final image = await stftToImage(frames);

      if (!mounted) return;
      setState(() {
        _signal = signal;
        _stftImage = image;
        _status =
            'Generated ${signal.length} samples, STFT: ${spec.frames} frames x ${spec.bins} bins';
      });
    } finally {
      stft.close();
    }
  }

  Future<void> _play() async {
    if (_signal.isEmpty) {
      setState(() => _status = 'Generate a signal first');
      return;
    }
    final sampleRate = int.tryParse(_sampleRateCtrl.text.trim()) ?? 16000;
    final wavBytes = WavWriter.encodeBytes(
      _signal,
      sampleRate: sampleRate,
      channels: 1,
      audioFormat: 1,
      bitsPerSample: 16,
    );

    try {
      final tempDir = await getTemporaryDirectory();
      await tempDir.create(recursive: true);
      final wavFile = File('${tempDir.path}/open_dspc_generated_signal.wav');
      await wavFile.parent.create(recursive: true);
      await wavFile.writeAsBytes(wavBytes, flush: true);

      await _player.stop();
      await _player.play(DeviceFileSource(wavFile.path, mimeType: 'audio/wav'));

      if (!mounted) return;
      setState(() {
        _isPlaying = true;
        _status = 'Playing generated signal';
      });

      _player.onPlayerComplete.first.then((_) {
        if (!mounted) return;
        setState(() => _isPlaying = false);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _status = 'Playback failed: $error';
      });
      if (kDebugMode) debugPrint('Playback failed: $error');
    }
  }

  Future<void> _stop() async {
    await _player.stop();
    if (!mounted) return;
    setState(() {
      _isPlaying = false;
      _status = 'Playback stopped';
    });
  }

  int _nextPow2(int x) {
    var n = 1;
    while (n < x) {
      n <<= 1;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 190,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Signal',
                    border: OutlineInputBorder(),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<_SignalKind>(
                      isExpanded: true,
                      value: _kind,
                      items: const [
                        DropdownMenuItem(
                          value: _SignalKind.sine,
                          child: Text('Sine'),
                        ),
                        DropdownMenuItem(
                          value: _SignalKind.cosine,
                          child: Text('Cosine'),
                        ),
                        DropdownMenuItem(
                          value: _SignalKind.sawtooth,
                          child: Text('Sawtooth'),
                        ),
                        DropdownMenuItem(
                          value: _SignalKind.pulseTrain,
                          child: Text('Pulse train'),
                        ),
                        DropdownMenuItem(
                          value: _SignalKind.whiteNoise,
                          child: Text('White noise'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _kind = value);
                      },
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _sampleRateCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: false,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Sample Rate',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _frequencyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Frequency (Hz)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _durationCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Duration (s)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _amplitudeCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amplitude (0..1)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _generate,
                icon: const Icon(Icons.auto_graph),
                label: const Text('Generate + STFT'),
              ),
              ElevatedButton.icon(
                onPressed: _play,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play'),
              ),
              ElevatedButton.icon(
                onPressed: _isPlaying ? _stop : null,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_status),
          const SizedBox(height: 16),
          if (_signal.isNotEmpty)
            SizedBox(
              height: 150,
              child: PlotWidget(y: _signal, width: 900, height: 150),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _stftImage == null
                  ? const Center(
                      child: Text(
                        'Generate a signal to view STFT (viridis, auto min/max).',
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              child: StftView(_stftImage!),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
