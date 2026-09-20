import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/diagnostics/diagnostics.dart';
import 'core/notifications/notification_service.dart';
import 'core/pet/pet_platform.dart';
import 'core/state/app_lifecycle.dart';
import 'core/state/device_controller.dart';
import 'core/state/settings_controller.dart';
import 'core/state/update_controller.dart';
import 'core/storage/device_repository.dart';
import 'core/storage/secret_store.dart';
import 'core/storage/settings_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // First thing, so a failure during startup is already being recorded.
  final diagnostics = Diagnostics.instance;
  await diagnostics.load();
  diagnostics.info('App', 'process started');

  final settings = SettingsController(repository: SettingsRepository());
  await settings.load();

  final devices = DeviceController(
    repository: DeviceRepository(),
    secrets: SecretStore(),
  );
  await devices.load(initialActiveDeviceId: settings.settings.activeDeviceId);

  final notifications = NotificationService();
  await notifications.init();

  final lifecycle = AppLifecycleObserver()..attach();

  final updates = UpdateController();
  await updates.loadCurrentVersion();

  runApp(
    MultiProvider(
      providers: [
        Provider<NotificationService>.value(value: notifications),
        Provider<AppLifecycleObserver>.value(value: lifecycle),
        Provider<PetPlatform>(create: (_) => PetPlatform()),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<DeviceController>.value(value: devices),
        ChangeNotifierProvider<UpdateController>.value(value: updates),
      ],
      child: const DshMobileApp(),
    ),
  );
}
