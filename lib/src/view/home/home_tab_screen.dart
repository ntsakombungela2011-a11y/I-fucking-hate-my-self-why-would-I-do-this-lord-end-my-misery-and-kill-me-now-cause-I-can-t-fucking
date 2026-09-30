import 'package:lichess_mobile/src/model/common/chess.dart' show Variant;
import 'package:flutter/material.dart';
import 'package:lichess_mobile/src/model/analysis/analysis_controller.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_angle.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_theme.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/analysis/analysis_screen.dart';
import 'package:lichess_mobile/src/view/offline_computer/offline_computer_game_screen.dart';
import 'package:lichess_mobile/src/view/puzzle/puzzle_screen.dart';
import 'package:lichess_mobile/src/view/settings/settings_screen.dart';

/// The offline-only home tab.
///
/// This intentionally contains no provider reads, network content, images, or
/// customizable home widgets so its first frame can render immediately.
class HomeTabScreen extends StatelessWidget {
  const HomeTabScreen({super.key, this.editModeEnabled = false});

  final bool editModeEnabled;

  static Route<dynamic> buildRoute({bool editModeEnabled = false}) {
    return buildScreenRoute(
      screen: HomeTabScreen(editModeEnabled: editModeEnabled),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BPC')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Welcome to BPC', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Choose an offline activity.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            _OfflineNavigationTile(
              icon: Icons.computer_outlined,
              title: 'Play Offline',
              onTap: () => Navigator.of(context).push(OfflineComputerGameScreen.buildRoute()),
            ),
            _OfflineNavigationTile(
              icon: Icons.extension_outlined,
              title: 'Puzzles',
              onTap: () => Navigator.of(context).push(
                PuzzleScreen.buildRoute(angle: const PuzzleTheme(PuzzleThemeKey.mix)),
              ),
            ),
            _OfflineNavigationTile(
              icon: Icons.analytics_outlined,
              title: 'Analysis',
              onTap: () => Navigator.of(context).push(
                AnalysisScreen.buildRoute(
                  AnalysisOptions.standalone(variant: Variant.standard),
                ),
              ),
            ),
            _OfflineNavigationTile(
              icon: Icons.settings_outlined,
              title: 'Settings',
              onTap: () => Navigator.of(context).push(SettingsScreen.buildRoute()),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineNavigationTile extends StatelessWidget {
  const _OfflineNavigationTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
