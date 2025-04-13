import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;

class SettingsProvider with ChangeNotifier {
  String _deviceName = 'LocalSend Device'; // Default name
  bool _loaded = false;

  String get deviceName => _deviceName;
  bool get isLoaded => _loaded;

  Future<void> loadDeviceName() async {
    if (_loaded) return; // Don't load multiple times

    final prefs = await SharedPreferences.getInstance();
    _deviceName = prefs.getString('deviceName') ?? await _getDefaultDeviceName();
    _loaded = true;
    notifyListeners(); // Notify after loading
    debugPrint("Loaded device name: $_deviceName");
  }

  Future<void> setDeviceName(String name) async {
    if (name.isEmpty) return;
    _deviceName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('deviceName', _deviceName);
    notifyListeners();
    debugPrint("Saved device name: $_deviceName");

    // Important: Signal discovery service to re-advertise with the new name
    // (Implementation depends on DiscoveryProvider)
  }

  Future<String> _getDefaultDeviceName() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isWindows) {
        WindowsDeviceInfo windowsInfo = await deviceInfo.windowsInfo;
        return windowsInfo.computerName;
      } else if (Platform.isMacOS) {
        MacOsDeviceInfo macOsInfo = await deviceInfo.macOsInfo;
        return macOsInfo.computerName;
      } else if (Platform.isLinux) {
        LinuxDeviceInfo linuxInfo = await deviceInfo.linuxInfo;
        return linuxInfo.prettyName; // Or machineId, or name
      }
    } catch (e) {
      debugPrint("Error getting device name: $e");
    }
    return 'LocalSend Device'; // Fallback
  }
}