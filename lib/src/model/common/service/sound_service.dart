import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/settings/general_preferences.dart';
import 'package:lichess_mobile/src/model/settings/preferences_storage.dart';
import 'package:logging/logging.dart';
import 'package:sound_effect/sound_effect.dart';

/// Maximum number of concurrent sounds that can be played.
const _kMaxConcurrentStreams = 2;

final _soundEffectPlugin = SoundEffect();

final _logger = Logger('SoundService');

// Must match name of files in assets/sounds/standard
enum Sound {
  move,
  capture,
  explosion,
  lowTime,
  dong,
  error,
  confirmation,
  puzzleStormEnd,
  clock,
  berserk,
}

/// A provider for [SoundService].
final soundServiceProvider = Provider<SoundService>((Ref ref) {
  final service = SoundService(ref);
  ref.onDispose(() => service.release());
  return service;
}, name: 'SoundServiceProvider');

final _extension = defaultTargetPlatform == TargetPlatform.iOS ? 'aifc' : 'mp3';

Future<void>? _soundEngineInitialization;
SoundTheme? _loadedSoundTheme;
final Map<Sound, Future<void>> _soundLoads = {};

/// Loads a single sound from the given [SoundTheme].
Future<void> _loadSound(SoundTheme theme, Sound sound) async {
  final themePath = 'assets/sounds/${theme.name}';
  const standardPath = 'assets/sounds/standard';
  final soundId = sound.name;
  final file = '$soundId.$_extension';
  String fullPath = '$themePath/$file';
  // Load only the requested sound and fall back to the standard asset when needed.
  try {
    await rootBundle.load(fullPath);
  } catch (_) {
    fullPath = '$standardPath/$file';
  }
  await _soundEffectPlugin.load(soundId, fullPath);
}

Future<void> _ensureSoundLoaded(SoundTheme theme, Sound sound) {
  if (_loadedSoundTheme != theme) {
    _loadedSoundTheme = theme;
    _soundLoads.clear();
  }
  return _soundLoads.putIfAbsent(sound, () => _loadSound(theme, sound));
}

/// Service to play game sounds.
class SoundService {
  SoundService(this._ref);

  final Ref _ref;

  /// Initialize the sound service.
  ///
  /// Initializes the audio engine without decoding any sound assets.
  static Future<void> initialize() {
    return _soundEngineInitialization ??= _initializeEngine();
  }

  static Future<void> _initializeEngine() async {
    try {
      await _soundEffectPlugin.initialize(maxStreams: _kMaxConcurrentStreams);
    } catch (e) {
      _logger.warning('Failed to initialize sound service: $e');
    }
  }

  /// Play the given sound if sound is enabled.
  Future<void> play(Sound sound, {double volume = 1.0}) async {
    assert((volume >= 0.0) && (volume <= 1.0));
    final isEnabled = _ref.read(generalPreferencesProvider).isSoundEnabled;
    final finalVolume = _ref.read(generalPreferencesProvider).masterVolume * volume;
    if (!isEnabled || finalVolume == 0.0) {
      return;
    }
    await initialize();
    await _ensureSoundLoaded(_ref.read(generalPreferencesProvider).soundTheme, sound);
    _soundEffectPlugin.play(sound.name, volume: finalVolume);
  }

  /// Play the capture sound for the given chess [variant].
  Future<void> playCaptureSound(Variant variant, {double volume = 1.0}) async {
    await play(variant == Variant.atomic ? Sound.explosion : Sound.capture, volume: volume);
  }

  /// Change the sound theme and optionally play a move sound.
  ///
  /// This will release the previous sounds and load the new ones.
  ///
  /// If [playSound] is true, a move sound will be played.
  Future<void> changeTheme(SoundTheme theme, {bool playSound = false}) async {
    await _soundEffectPlugin.release();
    _soundEngineInitialization = null;
    _loadedSoundTheme = null;
    _soundLoads.clear();
    await initialize();
    if (playSound) {
      await _ensureSoundLoaded(theme, Sound.move);
      _soundEffectPlugin.play(Sound.move.name);
    }
  }

  Future<void> release() async {
    await _soundEffectPlugin.release();
    _soundEngineInitialization = null;
    _loadedSoundTheme = null;
    _soundLoads.clear();
  }
}
