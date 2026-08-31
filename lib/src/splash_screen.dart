import 'dart:math' as math;

import 'package:flutter/material.dart';

class FlutterSplashScreen extends StatefulWidget {
  const FlutterSplashScreen({super.key});

  @override
  State<FlutterSplashScreen> createState() => _FlutterSplashScreenState();
}

class _FlutterSplashScreenState extends State<FlutterSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;

    return ColoredBox(
      color: isDark ? Colors.black : Colors.white,
      child: Center(
        child: SizedBox.square(
          dimension: 256,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => CustomPaint(
              painter: _SplashLogoPainter(
                progress: _controller.value,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashLogoPainter extends CustomPainter {
  _SplashLogoPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  static final List<Path> _paths = [
    Path()
      ..moveTo(118, 655)
      ..cubicTo(108, 600, 118, 545, 155, 495)
      ..cubicTo(195, 440, 260, 380, 340, 340)
      ..cubicTo(400, 310, 460, 288, 520, 285)
      ..cubicTo(610, 282, 700, 315, 780, 365)
      ..cubicTo(850, 408, 905, 460, 935, 500)
      ..cubicTo(944, 513, 949, 522, 947, 528)
      ..cubicTo(945, 534, 935, 542, 918, 552)
      ..cubicTo(900, 563, 875, 578, 850, 592)
      ..cubicTo(740, 642, 590, 675, 440, 690)
      ..cubicTo(340, 700, 250, 698, 190, 683)
      ..cubicTo(150, 673, 125, 663, 118, 655)
      ..close(),
    Path()
      ..moveTo(210, 430)
      ..cubicTo(205, 390, 250, 345, 320, 322)
      ..cubicTo(380, 302, 445, 305, 480, 335)
      ..cubicTo(505, 357, 495, 390, 455, 415)
      ..cubicTo(405, 447, 330, 458, 270, 450)
      ..cubicTo(235, 445, 213, 440, 210, 430)
      ..close(),
    Path()
      ..moveTo(300, 600)
      ..cubicTo(410, 485, 520, 395, 610, 355)
      ..cubicTo(680, 324, 745, 328, 810, 375)
      ..cubicTo(865, 415, 908, 462, 935, 505),
    Path()
      ..moveTo(315, 628)
      ..cubicTo(435, 525, 555, 450, 655, 415)
      ..cubicTo(725, 391, 782, 400, 830, 438)
      ..cubicTo(870, 469, 903, 495, 927, 517),
    Path()
      ..moveTo(335, 648)
      ..cubicTo(460, 568, 575, 512, 675, 492)
      ..cubicTo(745, 478, 795, 486, 838, 507)
      ..cubicTo(872, 523, 902, 527, 923, 527),
    Path()
      ..moveTo(165, 685)
      ..cubicTo(320, 680, 490, 655, 650, 615)
      ..cubicTo(740, 592, 815, 565, 875, 540),
    Path()
      ..moveTo(128, 640)
      ..cubicTo(145, 610, 158, 585, 160, 560),
    Path()
      ..moveTo(150, 662)
      ..cubicTo(168, 622, 182, 595, 185, 568),
  ];

  static final List<double> _lengths = [
    for (final path in _paths)
      path.computeMetrics().fold(0.0, (length, metric) => length + metric.length),
  ];

  static final double _totalLength = _lengths.fold(0.0, (total, length) => total + length);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 1024;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.scale(scale);

    var start = 0.0;
    for (var index = 0; index < _paths.length; index++) {
      final portion = _lengths[index] / _totalLength;
      final pathProgress = ((progress - start) / portion).clamp(0.0, 1.0).toDouble();
      _paintPartialPath(canvas, _paths[index], _lengths[index] * pathProgress, paint);
      start += portion;
    }
  }

  void _paintPartialPath(Canvas canvas, Path path, double length, Paint paint) {
    var remainingLength = length;
    for (final metric in path.computeMetrics()) {
      if (remainingLength <= 0) {
        return;
      }
      final extractedLength = math.min(remainingLength, metric.length);
      canvas.drawPath(metric.extractPath(0, extractedLength), paint);
      remainingLength -= extractedLength;
    }
  }

  @override
  bool shouldRepaint(_SplashLogoPainter oldDelegate) =>
      progress != oldDelegate.progress || color != oldDelegate.color;
}
