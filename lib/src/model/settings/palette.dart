import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/binding.dart';
import 'package:lichess_mobile/src/model/settings/preferences_storage.dart';

const kDefaultPaletteName = 'Bullet Express';

const kDefaultPalette = AppPalette(
  name: kDefaultPaletteName,
  category: 'Train/Transit',
  primary: Color(0xff0D1B3E),
  accent: Color(0xffE8622C),
  background: Color(0xffF5F6F8),
  surface: Color(0xffFFFFFF),
  text: Color(0xff0A1226),
  meta: 'A3 requester gave names; prior-session hex derivation used as supplied in Appendix A.',
);

/// The full catalog is only loaded by the palette picker.
final palettesProvider = FutureProvider<List<AppPalette>>((ref) async {
  final data = await rootBundle.loadString('assets/themes/palettes.json');
  return compute(_decodePalettes, data);
});

final activePaletteProvider = Provider<AppPalette>((ref) {
  return ref.watch(themePalettePreferenceProvider);
});

final themePalettePreferenceProvider = NotifierProvider<ThemePalettePreferenceNotifier, AppPalette>(
  ThemePalettePreferenceNotifier.new,
  name: 'ThemePalettePreferenceProvider',
);

class ThemePalettePreferenceNotifier extends Notifier<AppPalette> {
  @override
  AppPalette build() {
    final stored = LichessBinding.instance.sharedPreferences.getString(
      PrefCategory.themePalette.storageKey,
    );
    return stored == null ? kDefaultPalette : AppPalette.fromStoredJson(stored);
  }

  Future<void> setPalette(AppPalette palette) async {
    state = palette;
    await LichessBinding.instance.sharedPreferences.setString(
      PrefCategory.themePalette.storageKey,
      jsonEncode(palette.toJson()),
    );
  }
}

List<AppPalette> _decodePalettes(String data) {
  final list = jsonDecode(data) as List<dynamic>;
  return list.map((item) => AppPalette.fromJson(item as Map<String, dynamic>)).toList();
}

@immutable
class AppPalette {
  const AppPalette({
    required this.name,
    required this.category,
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
      category: json['category'] as String,
      primary: _parseColor(json['primary'] as String),
      accent: _parseColor(json['accent'] as String),
      background: _parseColor(json['background'] as String),
      surface: _parseColor(json['surface'] as String),
      text: _parseColor(json['text'] as String),
      meta: json['_meta'] as String?,
    );
  }

  factory AppPalette.fromStoredJson(String stored) {
    try {
      final json = jsonDecode(stored);
      return json is Map<String, dynamic> ? AppPalette.fromJson(json) : kDefaultPalette;
    } on FormatException {
      // Versions before palette persistence stored only the palette name.
      return kDefaultPalette;
    }
  }

  final String name;
  final String category;
  final Color primary;
  final Color accent;
  final Color background;
  final Color surface;
  final Color text;
  final String? meta;

  Map<String, String> toJson() => {
    'name': name,
    'category': category,
    'primary': _colorToHex(primary),
    'accent': _colorToHex(accent),
    'background': _colorToHex(background),
    'surface': _colorToHex(surface),
    'text': _colorToHex(text),
    if (meta case final meta?) '_meta': meta,
  };

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

String _colorToHex(Color color) =>
    '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

Color _onColor(Color color) {
  return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
      ? Colors.white
      : Colors.black;
}
