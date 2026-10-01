import 'dart:async' show Future, unawaited;
import 'dart:io' show Directory;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/binding.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/db/secure_storage.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/auth/auth_storage.dart';
import 'package:lichess_mobile/src/utils/string.dart';
import 'package:lichess_mobile/src/utils/system.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationDocumentsDirectory, getApplicationSupportDirectory;

typedef PreloadedData = ({
  PackageInfo packageInfo,
  BaseDeviceInfo deviceInfo,
  AuthUser? authUser,
  String sri,
  int engineMaxMemoryInMb,
  Directory? appDocumentsDirectory,
  Directory? appSupportDirectory,
});

PreloadedData? _cachedPreloadedData;
Future<PreloadedData>? _preloadedDataHydration;

/// Provides local defaults immediately, then refreshes them from device storage.
///
/// The initial value deliberately does not wait for platform channels, secure
/// storage, or any network request. This lets the application render while the
/// local cache is refreshed in the background.
final preloadedDataProvider = FutureProvider<PreloadedData>((Ref ref) {
  final cachedData = _cachedPreloadedData;
  if (cachedData != null) {
    return cachedData;
  }

  final localData = _localPreloadedData();
  _cachedPreloadedData = localData;
  _preloadedDataHydration ??= _hydratePreloadedData(
    localData,
    ref.read(authStorageProvider),
  );
  unawaited(_refreshPreloadedData(ref));

  return localData;
}, name: 'PreloadedDataProvider');

Future<void> _refreshPreloadedData(Ref ref) async {
  try {
    _cachedPreloadedData = await _preloadedDataHydration!;
    if (ref.mounted) {
      ref.invalidateSelf();
    }
  } catch (_) {
    // The synchronous local value remains available when a platform cache fails.
  }
}

PreloadedData _localPreloadedData() {
  final preferences = LichessBinding.instance.sharedPreferences;
  final sri = preferences.getString(kSRIStorageKey) ?? genRandomString(12);

  // Keep the locally generated SRI stable before secure storage is available.
  unawaited(preferences.setString(kSRIStorageKey, sri));

  return (
    packageInfo: PackageInfo(
      appName: 'lichess_mobile',
      version: '0.0.0',
      buildNumber: '0',
      packageName: 'lichess_mobile',
    ),
    deviceInfo: BaseDeviceInfo({
      'name': 'unknown',
      'model': 'unknown',
      'manufacturer': 'unknown',
      'systemName': 'unknown',
      'systemVersion': 'unknown',
      'identifierForVendor': 'unknown',
      'isPhysicalDevice': false,
    }),
    authUser: null,
    sri: sri,
    engineMaxMemoryInMb: 256,
    appDocumentsDirectory: null,
    appSupportDirectory: null,
  );
}

Future<PreloadedData> _hydratePreloadedData(
  PreloadedData localData,
  AuthStorage authStorage,
) async {
  final pInfo = await PackageInfo.fromPlatform();
  final deviceInfo = await DeviceInfoPlugin().deviceInfo;

  // Generate a socket random identifier and store it for the app lifetime
  String? storedSri;
  try {
    storedSri = await SecureStorage.instance.read(key: kSRIStorageKey);
    if (storedSri == null) {
      await SecureStorage.instance.write(key: kSRIStorageKey, value: localData.sri);
      storedSri = localData.sri;
    }
  } on PlatformException catch (_) {
    // Clear all secure storage if an error occurs because it probably means the key has
    // been lost
    await SecureStorage.instance.deleteAll();
  }

  final sri = storedSri ?? localData.sri;

  final authUser = await authStorage.read();

  final physicalMemory = await System.instance.getTotalRam() ?? 256.0;
  final engineMaxMemory = (physicalMemory / 10).ceil();

  Directory? appDocumentsDirectory;
  try {
    appDocumentsDirectory = await getApplicationDocumentsDirectory();
  } catch (_) {}

  Directory? appSupportDirectory;
  try {
    appSupportDirectory = await getApplicationSupportDirectory();
  } catch (_) {}

  return (
    packageInfo: pInfo,
    deviceInfo: deviceInfo,
    authUser: authUser,
    sri: sri,
    engineMaxMemoryInMb: engineMaxMemory,
    appDocumentsDirectory: appDocumentsDirectory,
    appSupportDirectory: appSupportDirectory,
  );
}
