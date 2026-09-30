import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n_esperanto/l10n_esperanto.dart';
import 'package:lichess_mobile/l10n/l10n.dart';
import 'package:lichess_mobile/src/binding.dart';
import 'package:lichess_mobile/src/debug/startup_debugger.dart';
import 'package:lichess_mobile/src/model/analysis/analysis_preferences.dart';
import 'package:lichess_mobile/src/model/broadcast/broadcast_preferences.dart';
import 'package:lichess_mobile/src/model/log/app_log_service.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/settings/general_preferences.dart';
import 'package:lichess_mobile/src/model/settings/palette.dart';
import 'package:lichess_mobile/src/model/study/study_preferences.dart';
import 'package:lichess_mobile/src/quick_actions.dart';
import 'package:lichess_mobile/src/shared_pgn_service.dart';
import 'package:lichess_mobile/src/tab_scaffold.dart';
import 'package:lichess_mobile/src/theme.dart';
import 'package:lichess_mobile/src/utils/screen.dart';

/// Application initialization and main entry point.
class AppInitializationScreen extends ConsumerWidget {
  const AppInitializationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Remove splash ASAP after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
      StartupDebugger.updateStep('Splash Removed');
    });

    // Application handles data loading after the first frame is rendered.
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(children: [Application(), StartupDebugger()]),
    );
  }
}

/// The main application widget.
///
/// This widget is the root of the application and is responsible for setting up
/// the theme, locale, and other global settings.
class Application extends ConsumerStatefulWidget {
  const Application({super.key});

  @override
  ConsumerState<Application> createState() => _AppState();
}

class _AppState extends ConsumerState<Application> {
  // DISABLED FOR OFFLINE MODE - REENABLE IF ONLINE FEATURES RETURNED
  // Whether the app has checked for online status for the first time.
  // bool _firstTimeOnlineCheck = false;
  final _navigatorKey = GlobalKey<NavigatorState>();

  // Adjusts some settings for small screens based on the MediaQuery data.
  Future<void> _screenSizeBasedInitialization(WidgetRef ref) async {
    const kDoneScreenSizeInitKey = 'done_screen_size_init_v4_dynamic_fix';

    final prefs = LichessBinding.instance.sharedPreferences;
    if (prefs.getBool(kDoneScreenSizeInitKey) == true) {
      return;
    }

    final mediaQueryData = MediaQueryData.fromView(
      WidgetsBinding.instance.platformDispatcher.views.first,
    );
    final isTablet = mediaQueryData.size.shortestSide > 600;
    final heightMinusBoard = estimateHeightMinusBoard(mediaQueryData);
    final isSmallScreen = heightMinusBoard < kSmallHeightMinusBoard;
    final showEngineLines = isTablet || heightMinusBoard > kSmallHeightMinusBoard - 30;
    final smallBoard = isTablet || isSmallScreen;

    await ref
        .read(analysisPreferencesProvider.notifier)
        .save(
          ref
              .read(analysisPreferencesProvider)
              .copyWith(smallBoard: smallBoard, showEngineLines: showEngineLines),
        );
    await ref
        .read(studyPreferencesProvider.notifier)
        .save(
          ref
              .read(studyPreferencesProvider)
              .copyWith(smallBoard: smallBoard, showEngineLines: showEngineLines),
        );
    await ref
        .read(broadcastPreferencesProvider.notifier)
        .save(
          ref
              .read(broadcastPreferencesProvider)
              .copyWith(smallBoard: smallBoard, showEngineLines: showEngineLines),
        );

    await prefs.setBool(kDoneScreenSizeInitKey, true);
  }

  @override
  void initState() {
    super.initState();

    StartupDebugger.updateStep('Starting Services');
    _screenSizeBasedInitialization(ref).ignore();

    // Start services
    ref.read(appLogServiceProvider).start();
    ref.read(quickActionServiceProvider).start();
    ref.read(sharedPgnServiceProvider).start().ignore();
    StartupDebugger.updateStep('Services Started');

    // DISABLED FOR OFFLINE MODE - REENABLE IF ONLINE FEATURES RETURNED
    // ref.read(notificationServiceProvider).start();
    // ref.read(messageServiceProvider).start();
    // ref.read(challengeServiceProvider).start();
    // ref.read(accountServiceProvider).start();
    // ref.read(correspondenceServiceProvider).start();
    // ref.read(announceServiceProvider).start();
    // ref.read(appLinksServiceProvider).start();

    // DISABLED FOR OFFLINE MODE - REENABLE IF ONLINE FEATURES RETURNED
    /*
    // Listen for connectivity changes and perform actions accordingly.
    ref.listenManual(connectivityChangesProvider, (prev, current) async {
      final prevWasOffline = prev?.value?.isOnline == false;
      final currentIsOnline = current.value?.isOnline == true;

      // Play registered moves whenever the app comes back online.
      if (prevWasOffline && currentIsOnline) {
        final nbMovesPlayed = await ref.read(correspondenceServiceProvider).playRegisteredMoves();
        if (nbMovesPlayed > 0) {
          ref.invalidate(ongoingGamesProvider);
        }
      }

      // Perform actions once when the app comes online.
      if (current.value?.isOnline == true && !_firstTimeOnlineCheck) {
        _firstTimeOnlineCheck = true;
        ref.read(correspondenceServiceProvider).syncGames();
      }

      final socketClient = ref.read(socketPoolProvider).currentClient;
      if (current.value?.isOnline == true &&
          current.value?.appState == AppLifecycleState.resumed &&
          !socketClient.isActive) {
        socketClient.connect();
      } else if (current.value?.isOnline == false) {
        socketClient.close();
      }
    });
    */
  }

  @override
  Widget build(BuildContext context) {
    final generalPrefs = ref.watch(generalPreferencesProvider);
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final activePalette = ref.watch(activePaletteProvider);
    final theme = makeAppTheme(context, generalPrefs, boardPrefs, appPalette: activePalette);

    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    return MaterialApp(
      navigatorKey: _navigatorKey,
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        MaterialLocalizationsEo.delegate,
        CupertinoLocalizationsEo.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      title: 'lichess.org',
      locale: generalPrefs.locale,
      theme: theme.copyWith(
        navigationBarTheme: isIOS
            ? null
            : NavigationBarTheme.of(
                context,
              ).copyWith(height: isShortVerticalScreen(context) ? 60 : null),
      ),
      home: const MainTabScaffold(),
      navigatorObservers: [rootNavPageRouteObserver],
    );
  }
}
