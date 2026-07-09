import 'package:dartchess/dartchess.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/account_repository.dart';
import 'package:lichess_mobile/src/model/analysis/analysis_controller.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/message/message_repository.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/tab_scaffold.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/account/account_menu.dart';
import 'package:lichess_mobile/src/view/account/profile_screen.dart';
import 'package:lichess_mobile/src/view/analysis/analysis_screen.dart';
import 'package:lichess_mobile/src/view/board_editor/board_editor_screen.dart';
import 'package:lichess_mobile/src/view/clock/clock_tool_screen.dart';
import 'package:lichess_mobile/src/view/explorer/opening_explorer_screen.dart';
import 'package:lichess_mobile/src/view/message/contacts_screen.dart';
import 'package:lichess_mobile/src/view/more/import_pgn_screen.dart';
import 'package:lichess_mobile/src/view/relation/friend_screen.dart';
import 'package:lichess_mobile/src/view/settings/settings_screen.dart';
import 'package:lichess_mobile/src/view/user/player_screen.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/settings.dart';
import 'package:lichess_mobile/src/widgets/user.dart';
import 'package:url_launcher/url_launcher.dart';

class MoreTabScreen extends ConsumerWidget {
  const MoreTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) {
          ref.read(currentBottomTabProvider.notifier).state = BottomTab.home;
        }
      },
      child: PlatformScaffold(
        appBar: PlatformAppBar(
          title: Theme.of(context).platform == TargetPlatform.iOS
              ? AppBarLichessTitle(
                  iconSize:
                      Theme.of(context).textTheme.headlineSmall?.fontSize ?? 24,
                )
              : const AppBarLichessTitle(),
          centerTitle: false,
          titleTextStyle: Theme.of(context).platform == TargetPlatform.iOS
              ? Theme.of(context).textTheme.headlineSmall
              : null,
          actions: const [],
        ),
        body: const _Body(),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(onlineStatusProvider).value ?? false;
    final authUser = ref.watch(authControllerProvider);

    return ListTileTheme.merge(
      iconColor: Theme.of(context).colorScheme.primary,
      child: ListView(
        controller: moreScrollController,
        children: [
          ListSection(
            header: SettingsSectionTitle(context.l10n.tools),
            hasLeading: true,
            children: [
              ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.importPgn),
                onTap: () =>
                    Navigator.of(context).push(ImportPgnScreen.buildRoute()),
              ),
              ListTile(
                leading: const Icon(Icons.biotech_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.analysis),
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  AnalysisScreen.buildRoute(
                    const AnalysisOptions.standalone(variant: Variant.standard),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.explore_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.openingExplorer),
                enabled: isOnline,
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  OpeningExplorerScreen.buildRoute(
                    const AnalysisOptions.pgn(
                      id: StringId('standalone_opening_explorer'),
                      orientation: Side.white,
                      pgn: '',
                      isComputerAnalysisAllowed: false,
                      variant: Variant.standard,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.boardEditor),
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  BoardEditorScreen.buildRoute((
                    initialVariant: Variant.standard,
                    initialFen: null,
                    initialOrientation: null,
                  )),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.alarm_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.clock),
                onTap: () {
                  Navigator.of(
                    context,
                    rootNavigator: true,
                  ).push(ClockToolScreen.buildRoute());
                },
              ),
            ],
          ),
          const SizedBox.shrink(),
          const _AccountSection(),
          const SizedBox.shrink(),
          Padding(
            padding: Styles.bodySectionPadding,
            child: LichessMessage(style: TextTheme.of(context).bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    return ListSection(
      hasLeading: true,
      children: [
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: Text(context.l10n.settingsSettings),
          trailing: isIOS ? const CupertinoListTileChevron() : null,
          onTap: () {
            Navigator.of(context).push(SettingsScreen.buildRoute());
          },
        ),
      ],
    );
  }
}
