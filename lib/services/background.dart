import 'package:flutter_background/flutter_background.dart';

/// Keeps OTP Flow alive when the app is in the background, so the
/// auto-refresh timer keeps running 24/7 without the screen being on.
class Background {
  static bool running = false;

  static Future<bool> enable() async {
    const config = FlutterBackgroundAndroidConfig(
      notificationTitle: 'OTP Flow is running',
      notificationText: 'Keeping your Meesho sessions signed in',
      // Quiet: this notification is a requirement of Android's foreground
      // service, not something worth buzzing about.
      notificationImportance: AndroidNotificationImportance.normal,
      enableWifiLock: true,
      showBadge: false,
    );
    try {
      final ok = await FlutterBackground.initialize(androidConfig: config);
      if (!ok) return false;
      running = await FlutterBackground.enableBackgroundExecution();
      return running;
    } catch (_) {
      return false;
    }
  }

  static Future<void> disable() async {
    try {
      if (FlutterBackground.isBackgroundExecutionEnabled) {
        await FlutterBackground.disableBackgroundExecution();
      }
    } catch (_) {}
    running = false;
  }
}
