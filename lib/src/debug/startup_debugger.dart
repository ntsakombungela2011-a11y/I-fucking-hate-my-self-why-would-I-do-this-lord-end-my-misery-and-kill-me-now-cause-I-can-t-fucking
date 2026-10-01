import 'dart:async';

import 'package:flutter/material.dart';

/// An on-screen startup timeline for diagnosing launch delays without logs.
class StartupDebugger extends StatefulWidget {
  const StartupDebugger({super.key});

  static String _currentStep = 'Init';
  static int _startTime = 0;
  static bool _isActive = false;
  static final ValueNotifier<int> _updates = ValueNotifier<int>(0);

  static void init() {
    _startTime = DateTime.now().millisecondsSinceEpoch;
    _currentStep = 'Init';
    _isActive = true;
    _updates.value++;
  }

  static void updateStep(String step) {
    if (_isActive) {
      _currentStep = step;
      _updates.value++;
    }
  }

  @override
  State<StartupDebugger> createState() => _StartupDebuggerState();
}

class _StartupDebuggerState extends State<StartupDebugger> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && StartupDebugger._isActive) {
        StartupDebugger._updates.value++;
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: StartupDebugger._updates,
      builder: (context, _, _) {
        if (!StartupDebugger._isActive) return const SizedBox.shrink();

        final elapsed =
            DateTime.now().millisecondsSinceEpoch - StartupDebugger._startTime;
        return Positioned(
          top: 50,
          left: 10,
          right: 10,
          child: Container(
            padding: const EdgeInsets.all(8),
            color: Colors.black.withValues(alpha: 0.7),
            child: Text(
              'STARTUP: ${StartupDebugger._currentStep}\nTIME: ${elapsed}ms',
              style: const TextStyle(
                color: Colors.greenAccent,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        );
      },
    );
  }
}
