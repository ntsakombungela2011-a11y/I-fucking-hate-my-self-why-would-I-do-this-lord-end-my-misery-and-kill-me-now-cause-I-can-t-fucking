import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/puzzle/offline_puzzle_repository.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_angle.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_theme.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/puzzle/puzzle_screen.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/platform_search_bar.dart';

final _themesProvider = FutureProvider.autoDispose<IMap<PuzzleThemeKey, int>>((
  ref,
) async {
  final repository = await ref.watch(offlinePuzzleRepositoryProvider.future);
  return repository.themeCounts();
});

class PuzzleThemesScreen extends StatelessWidget {
  const PuzzleThemesScreen({super.key});

  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const PuzzleThemesScreen());
  }

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      appBar: PlatformAppBar(title: Text(context.l10n.puzzlePuzzleThemes)),
      body: const _Body(),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body();

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // skip recommended category since we display it on the puzzle tab screen
    final list = ref.watch(puzzleThemeCategoriesProvider).skip(1).toList();
    final themes = ref.watch(_themesProvider);

    return themes.when(
      data: (data) {
        final savedThemes = data;
        final searchBar = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: PlatformSearchBar(
            controller: _searchController,
            hintText: context.l10n.search,
            onChanged: (String query) => setState(() => _searchQuery = query),
            onClear: () {
              _searchController.clear();
              setState(() => _searchQuery = '');
            },
          ),
        );

        if (_searchQuery.isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          final matched = [
            for (final (_, categoryThemes) in list)
              for (final theme in categoryThemes)
                if (theme
                        .l10n(context.l10n)
                        .name
                        .toLowerCase()
                        .contains(query) ||
                    theme
                        .l10n(context.l10n)
                        .description
                        .toLowerCase()
                        .contains(query))
                  theme,
          ];

          return ListView(
            children: [
              searchBar,
              ListSection(
                hasLeading: true,
                children: matched.map((theme) {
                  return _ThemeTile(theme: theme, savedThemes: savedThemes);
                }).toList(),
              ),
            ],
          );
        }

        return ListView(
          children: [
            searchBar,
            for (final category in list)
              _Category(category: category, savedThemes: savedThemes),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (error, stack) => const Center(
        child: Text('No offline puzzles are available for these themes.'),
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.theme, required this.savedThemes});

  final PuzzleThemeKey theme;
  final IMap<PuzzleThemeKey, int> savedThemes;

  @override
  Widget build(BuildContext context) {
    final themeCountStyle = TextStyle(
      fontSize: 12,
      color: textShade(context, Styles.subtitleOpacity),
    );

    return ListTile(
      enabled: savedThemes.containsKey(theme),
      leading: Icon(theme.icon),
      trailing: savedThemes.containsKey(theme)
          ? Padding(
              padding: const EdgeInsets.only(left: 6.0),
              child: Text('${savedThemes[theme]}', style: themeCountStyle),
            )
          : null,
      title: Text(theme.l10n(context.l10n).name),
      subtitle: Text(
        theme.l10n(context.l10n).description,
        maxLines: 10,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: textShade(context, Styles.subtitleOpacity)),
      ),
      onTap: savedThemes.containsKey(theme)
          ? () {
              Navigator.of(
                context,
                rootNavigator: true,
              ).push(PuzzleScreen.buildRoute(angle: PuzzleTheme(theme)));
            }
          : null,
    );
  }
}

class _Category extends StatelessWidget {
  const _Category({required this.category, required this.savedThemes});

  final PuzzleThemeCategory category;
  final IMap<PuzzleThemeKey, int> savedThemes;

  @override
  Widget build(BuildContext context) {
    final (categoryName, themes) = category;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(categoryName),
        children: [
          ListSection(
            hasLeading: true,
            children: themes.map((theme) {
              return _ThemeTile(theme: theme, savedThemes: savedThemes);
            }).toList(),
          ),
        ],
      ),
    );
  }
}
