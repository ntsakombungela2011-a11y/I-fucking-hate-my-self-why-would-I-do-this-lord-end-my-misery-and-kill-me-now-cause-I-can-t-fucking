import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/settings/palette.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/widgets/list.dart';

class PalettePickerScreen extends ConsumerWidget {
  const PalettePickerScreen({super.key});

  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const PalettePickerScreen());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palettes = ref.watch(palettesProvider);
    final selectedName = ref.watch(themePalettePreferenceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Palettes'), animateColor: true),
      body: palettes.when(
        data: (items) {
          final sections = <String, List<AppPalette>>{};
          for (final palette in items) {
            sections.putIfAbsent(palette.category, () => []).add(palette);
          }

          return ListView.builder(
            itemCount: sections.length,
            itemBuilder: (context, index) {
              final entry = sections.entries.elementAt(index);
              return ListSection(
                children: [
                  ExpansionTile(
                    title: Text(entry.key),
                    initiallyExpanded: entry.value.any((palette) => palette.name == selectedName),
                    children: [
                      _PaletteSectionList(palettes: entry.value, selectedName: selectedName),
                    ],
                  ),
                ],
              );
            },
          );
        },
        error: (error, stackTrace) => Center(child: Text('Could not load themes: $error')),
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      ),
    );
  }
}

class _PaletteSectionList extends StatelessWidget {
  const _PaletteSectionList({required this.palettes, required this.selectedName});

  static const _tileExtent = 80.0;

  final List<AppPalette> palettes;
  final String selectedName;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.6;
    final listHeight = math.min(palettes.length * _tileExtent, maxHeight);

    return SizedBox(
      height: listHeight,
      child: ListView.builder(
        primary: false,
        itemExtent: _tileExtent,
        itemCount: palettes.length,
        itemBuilder: (context, index) => _PaletteTile(
          palette: palettes[index],
          selectedName: selectedName,
        ),
      ),
    );
  }
}

class _PaletteTile extends ConsumerWidget {
  const _PaletteTile({required this.palette, required this.selectedName});

  final AppPalette palette;
  final String selectedName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RadioListTile<String>(
      value: palette.name,
      groupValue: selectedName,
      onChanged: (_) => ref.read(themePalettePreferenceProvider.notifier).setPalette(palette.name),
      title: Text(palette.name),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Row(
          children: [
            for (final color in palette.swatchColors)
              Container(
                width: 18,
                height: 18,
                margin: const EdgeInsetsDirectional.only(end: 6),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: ColorScheme.of(context).outlineVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
