import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/app.dart';
import 'package:lichess_mobile/src/binding.dart';
import 'package:lichess_mobile/src/debug/startup_debugger.dart';
import 'package:lichess_mobile/src/init.dart';
import 'package:lichess_mobile/src/intl.dart';
import 'package:lichess_mobile/src/model/common/service/sound_service.dart';
import 'package:lichess_mobile/src/model/log/app_log_service.dart';
import 'package:lichess_mobile/src/network/http.dart';

Future<void> main() async {
  StartupDebugger.init();
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  final lichessBinding = AppLichessBinding.ensureInitialized();
  StartupDebugger.updateStep('Binding Init');

  // 1. Preserve Native Splash Immediately
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // 2. ONLY Await Critical Path: SharedPreferences
  await lichessBinding.preloadSharedPreferences();
  StartupDebugger.updateStep('Prefs Loaded');

  // 3. RUN APP IMMEDIATELY
  StartupDebugger.updateStep('Running App');
  runApp(
    ProviderScope(
      observers: [ProviderLogger()],
      retry: (retryCount, error) {
        if (error is ServerException && error.statusCode != 503) return null;
        if (retryCount > 5) return null;
        return Duration(milliseconds: 500 * (1 << retryCount));
      },
      child: const AppInitializationScreen(),
    ),
  );

  // 4. DEFERRED INITIALIZATION (Fire-and-Forget)
  // These run AFTER the first frame is painted. They do NOT block startup.

  // A. Sounds
  SoundService.initialize().ignore();

  // B. Intl & Notifications (Delayed slightly to let UI breathe)
  setupIntl(widgetsBinding).then((locale) {
    Future.delayed(const Duration(seconds: 2), () {
      initializeLocalNotifications(locale).ignore();
    }).ignore();
  }).ignore();

  // C. Android Display Mode (Crucial for smoothness, but can wait 1s)
  if (defaultTargetPlatform == TargetPlatform.android) {
    Future.delayed(const Duration(seconds: 1), () {
      androidDisplayInitialization(widgetsBinding).ignore();
    }).ignore();
  }

  // D. Firebase & Piece Images: DISABLED FROM MAIN
  // preloadPieceImages() is NOT called here.
  // initializeFirebase() is NOT called here.
}
