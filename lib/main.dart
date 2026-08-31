import 'package:flutter/material.dart';

import 'app.dart';
import 'core/state/easytier_controller.dart';
import 'data/config/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load();

  // Build the backend (auto-selects service/FFI vs mock) and the controller
  // that bridges it to the UI.
  final controller = await EasyTierController.create();

  runApp(
    EasyTierApp(controller: controller),
  );

  // Optional: connect right away with the saved configuration.
  if (AppSettings.instance.autoStart && !controller.isRunning) {
    // Give the first frame a moment; the connect flow may raise the Android
    // VPN permission dialog, which needs the activity to be attached.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.start(AppSettings.instance.effectiveConfig);
    });
  }
}
