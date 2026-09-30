import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/app.dart';
import 'package:lichess_mobile/src/binding.dart';
import 'package:lichess_mobile/src/debug/startup_trace.dart';
import 'package:lichess_mobile/src/init.dart';
import 'package:lichess_mobile/src/intl.dart';
import 'package:lichess_mobile/src/model/common/service/sound_service.dart';
import 'package:lichess_mobile/src/model/log/app_log_service.dart';
import 'package:lichess_mobile/src/network/http.dart';

Future<void> main() async {
  StartupTrace.mark('main start');
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  final lichessBinding = AppLichessBinding.ensureInitialized();

  // 1. Preserve Splash immediately
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // 2. CRITICAL PATH ONLY (Must happen before runApp)
  // Shared Preferences are needed for theme/locale detection instantly.
  await lichessBinding.preloadSharedPreferences();
  StartupTrace.mark('shared preferences preloaded');

  // 3. RUN APP IMMEDIATELY
  StartupTrace.mark('before runApp');
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
  widgetsBinding.addPostFrameCallback((_) => StartupTrace.mark('first frame'));

  // 4. DEFERRED INITIALIZATION (Run AFTER first frame)
  preloadPieceImages().then((_) => debugPrint('Pieces preloaded'));
  SoundService.initialize().then((_) => debugPrint('Sounds ready'));
  setupIntl(widgetsBinding).then((locale) {
    initializeLocalNotifications(locale).then((_) => debugPrint('Notifs ready'));
  });

  // Firebase initialization is deferred while the app is offline-first.
  /*
  if (defaultTargetPlatform != TargetPlatform.linux) {
    lichessBinding.initializeFirebase().then((_) => debugPrint('Firebase ready'));
  }
  */

  if (defaultTargetPlatform == TargetPlatform.android) {
    androidDisplayInitialization(widgetsBinding).then((_) => debugPrint('Display ready'));
  }
}
