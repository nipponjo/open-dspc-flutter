import 'package:flutter/material.dart';
import 'package:open_dspc_example/fft_benchmark_panel.dart';
import 'package:open_dspc_example/signal_stft_panel.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('open_dspc example'),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'FFT Bench'),
                Tab(text: 'Signal + STFT'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [FftBenchmarkPanel(), SignalStftPanel()],
          ),
        ),
      ),
    );
  }
}
