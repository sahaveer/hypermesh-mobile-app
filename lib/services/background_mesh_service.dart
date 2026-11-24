import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackgroundMeshService {
  static const MethodChannel _channel = MethodChannel('com.hypermesh.player/background_service');
  static const String _keyEnabled = 'background_sharing_enabled_v1';
  static const String _keyAsked = 'background_sharing_asked_v1';

  static bool get isSupportedPlatform => !kIsWeb && Platform.isAndroid;

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnabled) ?? false;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, enabled);
  }

  static Future<bool> wasAsked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAsked) ?? false;
  }

  static Future<void> setWasAsked(bool asked) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAsked, asked);
  }

  static Future<bool> startService({required int filesCount, required int peersCount}) async {
    if (!isSupportedPlatform) return false;

    try {
      final success = await _channel.invokeMethod<bool>('startService', {
        'filesCount': filesCount,
        'peersCount': peersCount,
      });
      return success ?? false;
    } catch (e) {
      debugPrint("Error starting background mesh service: $e");
      return false;
    }
  }

  static Future<bool> updateService({required int filesCount, required int peersCount}) async {
    if (!isSupportedPlatform) return false;

    try {
      final success = await _channel.invokeMethod<bool>('updateService', {
        'filesCount': filesCount,
        'peersCount': peersCount,
      });
      return success ?? false;
    } catch (e) {
      debugPrint("Error updating background mesh service: $e");
      return false;
    }
  }

  static Future<bool> stopService() async {
    if (!isSupportedPlatform) return false;

    try {
      final success = await _channel.invokeMethod<bool>('stopService');
      return success ?? false;
    } catch (e) {
      debugPrint("Error stopping background mesh service: $e");
      return false;
    }
  }

  static Future<bool> isServiceRunning() async {
    if (!isSupportedPlatform) return false;

    try {
      final running = await _channel.invokeMethod<bool>('isServiceRunning');
      return running ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<String?> getAppSourceApkPath() async {
    if (!isSupportedPlatform) return null;
    try {
      final path = await _channel.invokeMethod<String>('getAppSourceApkPath');
      return path;
    } catch (e) {
      debugPrint("Error getting app APK path: $e");
      return null;
    }
  }

  static Future<bool> installApk(String filePath) async {
    if (!isSupportedPlatform) return false;
    try {
      final success = await _channel.invokeMethod<bool>('installApk', {'filePath': filePath});
      return success ?? false;
    } catch (e) {
      debugPrint("Error launching APK install: $e");
      return false;
    }
  }
}
