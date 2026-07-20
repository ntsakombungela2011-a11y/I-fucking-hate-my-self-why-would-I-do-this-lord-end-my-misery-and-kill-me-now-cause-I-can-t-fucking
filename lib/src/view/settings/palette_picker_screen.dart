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
      appBar: AppBar(title: const Text('Themes'), animateColor: true),
      body: palettes.when(
        data: (items) => ListView(
          children: [
            ListSection(
              children: [
                for (final palette in items)
                  RadioListTile<String>(
                    value: palette.name,
                    groupValue: selectedName,
                    onChanged: (_) => ref
                        .read(themePalettePreferenceProvider.notifier)
                        .setPalette(palette.name),
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
                  ),
              ],
            ),
          ],
        ),
        error: (error, stackTrace) => Center(child: Text('Could not load themes: $error')),
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      ),
    );
  }
}
