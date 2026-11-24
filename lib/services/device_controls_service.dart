import 'package:flutter/services.dart';

class DeviceControlsService {
  static const MethodChannel _channel = MethodChannel("com.hypermesh.player/device_controls");

  static Future<double> getScreenBrightness() async {
    try {
      final res = await _channel.invokeMethod<double>('getScreenBrightness');
      return res ?? 0.5;
    } catch (_) {
      return 0.5;
    }
  }

  static Future<void> setScreenBrightness(double brightness) async {
    try {
      await _channel.invokeMethod('setScreenBrightness', {
        'brightness': brightness.clamp(0.01, 1.0),
      });
    } catch (_) {}
  }

  static Future<void> resetScreenBrightness() async {
    try {
      await _channel.invokeMethod('resetScreenBrightness');
    } catch (_) {}
  }

  static Future<double> getDeviceVolume() async {
    try {
      final res = await _channel.invokeMethod<double>('getDeviceVolume');
      return res ?? 0.5;
    } catch (_) {
      return 0.5;
    }
  }

  static Future<void> setDeviceVolume(double volume) async {
    try {
      await _channel.invokeMethod('setDeviceVolume', {
        'volume': volume.clamp(0.0, 1.0),
      });
    } catch (_) {}
  }
}
