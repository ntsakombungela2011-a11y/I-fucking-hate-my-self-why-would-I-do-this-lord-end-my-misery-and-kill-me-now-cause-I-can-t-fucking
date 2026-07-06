import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/tab_scaffold.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/account/account_menu.dart';
import 'package:lichess_mobile/src/view/coordinate_training/coordinate_training_screen.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:material_symbols_icons/symbols.dart';

class LearnTabScreen extends ConsumerWidget {
  const LearnTabScreen({super.key});

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
          title: Text(context.l10n.learnMenu),
          centerTitle: false,
          titleTextStyle: Theme.of(context).platform == TargetPlatform.iOS
              ? Theme.of(context).textTheme.headlineSmall
              : null,
          actions: const [AccountMenuButton()],
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
    return ListTileTheme.merge(
      iconColor: Theme.of(context).colorScheme.primary,
      child: ListView(
        controller: learnScrollController,
        children: [
          // Placeholder for future Board Scanner feature (Step 6)
          ListSection(
            hasLeading: true,
            children: [
              ListTile(
                leading: const Icon(Symbols.where_to_vote),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.coordinatesCoordinateTraining, style: Styles.callout),
                onTap: () => Navigator.of(
                  context,
                  rootNavigator: true,
                ).push(CoordinateTrainingScreen.buildRoute()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
