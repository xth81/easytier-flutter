import 'package:flutter/material.dart';

import 'app.dart';
import 'core/state/easytier_controller.dart';
import 'data/config/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load();

  // Build the backend (auto-selects FFI vs mock) and the controller that
  // bridges it to the UI.
  final controller = await EasyTierController.create();

  runApp(
    EasyTierApp(controller: controller),
  );
}
