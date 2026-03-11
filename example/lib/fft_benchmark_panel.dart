import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import 'fft_benchmark_runner.dart';

class FftBenchmarkPanel extends StatefulWidget {
  const FftBenchmarkPanel({super.key});

  @override
  State<FftBenchmarkPanel> createState() => _FftBenchmarkPanelState();
}

class _FftBenchmarkPanelState extends State<FftBenchmarkPanel> {
  final _runner = FftBenchmarkRunner();
  bool _running = false;
  String _status = 'Ready';
  List<File> _reports = const [];

  @override
  void initState() {
    super.initState();
    _reloadReports();
  }

  Future<void> _reloadReports() async {
    final reports = await _runner.listReports();
    if (!mounted) return;
    setState(() {
      _reports = reports;
    });
  }

  Future<void> _startBenchmark() async {
    if (_running) return;

    setState(() {
      _running = true;
      _status = 'Starting benchmark...';
    });

    try {
      final result = await _runner.runAndSave(
        onProgress: (message) {
          if (!mounted) return;
          setState(() {
            _status = message;
          });
        },
      );

      await _reloadReports();

      if (!mounted) return;
      setState(() {
        _status =
            'Completed ${result.sizeCount} sizes, ${result.rowCount} rows. Saved ${result.csvFile.uri.pathSegments.last}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Benchmark failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
        });
      }
    }
  }

  Future<void> _deleteReport(File file) async {
    await file.delete();
    await _reloadReports();

    if (!mounted) return;
    setState(() {
      _status = 'Deleted ${file.uri.pathSegments.last}';
    });
  }

  Future<void> _showReportActions(File file) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('Open in app'),
                onTap: () async {
                  Navigator.of(context).pop();
                  final result = await OpenFilex.open(file.path);
                  if (!mounted) return;
                  setState(() {
                    _status = result.message.isNotEmpty
                        ? result.message
                        : 'Open result: ${result.type}';
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Share / Send'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await Share.shareXFiles([XFile(file.path)]);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: _running ? null : _startBenchmark,
            icon: _running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(_running ? 'Running...' : 'Run FFT Benchmark'),
          ),
          const SizedBox(height: 8),
          Text(_status),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Reports',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _reloadReports,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _reports.isEmpty
                ? const Center(child: Text('No reports yet.'))
                : ListView.builder(
                    itemCount: _reports.length,
                    itemBuilder: (context, index) {
                      final file = _reports[index];
                      return FutureBuilder<FileStat>(
                        future: file.stat(),
                        builder: (context, snapshot) {
                          final stat = snapshot.data;
                          final modified = stat?.modified;
                          final bytes = stat?.size;
                          final subtitle = [
                            if (modified != null) _formatDate(modified),
                            if (bytes != null)
                              '${(bytes / 1024).toStringAsFixed(1)} KB',
                          ].join('  |  ');

                          return ListTile(
                            onTap: () => _showReportActions(file),
                            leading: const Icon(Icons.description_outlined),
                            title: Text(file.uri.pathSegments.last),
                            subtitle: Text(subtitle),
                            trailing: IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _deleteReport(file),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
