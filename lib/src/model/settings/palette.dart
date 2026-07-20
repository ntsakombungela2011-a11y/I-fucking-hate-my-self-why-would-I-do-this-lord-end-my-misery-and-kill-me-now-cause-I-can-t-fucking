import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/binding.dart';
import 'package:lichess_mobile/src/model/settings/preferences_storage.dart';

const kDefaultPaletteName = 'Bullet Express';

final palettesProvider = FutureProvider<List<AppPalette>>((ref) async {
  final data = await rootBundle.loadString('assets/themes/palettes.json');
  final list = jsonDecode(data) as List<dynamic>;
  return list.map((item) => AppPalette.fromJson(item as Map<String, dynamic>)).toList();
});

final activePaletteProvider = Provider<AppPalette?>((ref) {
  final palettes = ref.watch(palettesProvider).value;
  if (palettes == null || palettes.isEmpty) return null;
  final selectedName = ref.watch(themePalettePreferenceProvider);
  return palettes.firstWhere(
    (palette) => palette.name == selectedName,
    orElse: () => palettes.firstWhere(
      (palette) => palette.name == kDefaultPaletteName,
      orElse: () => palettes.first,
    ),
  );
});

final themePalettePreferenceProvider = NotifierProvider<ThemePalettePreferenceNotifier, String>(
  ThemePalettePreferenceNotifier.new,
  name: 'ThemePalettePreferenceProvider',
);

class ThemePalettePreferenceNotifier extends Notifier<String> {
  @override
  String build() {
    return LichessBinding.instance.sharedPreferences.getString(
          PrefCategory.themePalette.storageKey,
        ) ??
        kDefaultPaletteName;
  }

  Future<void> setPalette(String paletteName) async {
    await LichessBinding.instance.sharedPreferences.setString(
      PrefCategory.themePalette.storageKey,
      paletteName,
    );
    state = paletteName;
  }
}

@immutable
class AppPalette {
  const AppPalette({
    required this.name,
    required this.primary,
    required this.accent,
    required this.background,
    required this.surface,
    required this.text,
    this.meta,
  });

  factory AppPalette.fromJson(Map<String, dynamic> json) {
    return AppPalette(
      name: json['name'] as String,
      primary: _parseColor(json['primary'] as String),
      accent: _parseColor(json['accent'] as String),
      background: _parseColor(json['background'] as String),
      surface: _parseColor(json['surface'] as String),
      text: _parseColor(json['text'] as String),
      meta: json['_meta'] as String?,
    );
  }

  final String name;
  final Color primary;
  final Color accent;
  final Color background;
  final Color surface;
  final Color text;
  final String? meta;

  Iterable<Color> get swatchColors => [primary, accent, background, surface, text];

  ColorScheme toColorScheme(Brightness brightness) {
    return ColorScheme.fromSeed(seedColor: primary, brightness: brightness).copyWith(
      primary: primary,
      onPrimary: _onColor(primary),
      secondary: accent,
      onSecondary: _onColor(accent),
      tertiary: accent,
      surface: surface,
      onSurface: text,
      surfaceContainerLowest: background,
      surfaceContainerLow: background,
      surfaceContainer: surface,
      surfaceContainerHigh: surface,
      surfaceContainerHighest: surface,
    );
  }
}

Color _parseColor(String hex) {
  final normalized = hex.replaceFirst('#', '');
  return Color(int.parse('ff$normalized', radix: 16));
}

Color _onColor(Color color) {
  return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
      ? Colors.white
      : Colors.black;
}
