import 'package:flutter/material.dart';

class _StartupMark {
  const _StartupMark(this.label, this.elapsed);

  final String label;
  final int elapsed;
}

/// An opt-in startup trace for CI performance builds.
class StartupTrace {
  StartupTrace._();

  static const enabled = bool.fromEnvironment('BPC_TRACE');
  static final _marks = <_StartupMark>[];
  static final _updates = ValueNotifier<int>(0);
  static Stopwatch? _stopwatch;

  static void mark(String label) {
    if (!enabled) return;
    final stopwatch = _stopwatch ??= Stopwatch()..start();
    final elapsed = stopwatch.elapsedMilliseconds;
    _marks.add(_StartupMark(label, elapsed));
    _updates.value++;
    debugPrint('BPC_STARTUP $label $elapsed');
  }
}

class StartupTraceOverlay extends StatelessWidget {
  const StartupTraceOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    if (!StartupTrace.enabled) return const SizedBox.shrink();

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SafeArea(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360, maxHeight: 280),
            color: Colors.black.withValues(alpha: 0.7),
            padding: const EdgeInsets.all(8),
            child: ValueListenableBuilder<int>(
              valueListenable: StartupTrace._updates,
              builder: (context, _, _) => ListView.builder(
                shrinkWrap: true,
                itemCount: StartupTrace._marks.length,
                itemBuilder: (context, index) {
                  final mark = StartupTrace._marks[index];
                  return Text(
                    '${mark.elapsed}ms  ${mark.label}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
