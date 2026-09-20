import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/l10n.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/pet/pet_platform.dart';
import '../../core/state/device_controller.dart';
import '../../core/state/settings_controller.dart';
import '../about/about_screen.dart';
import '../diagnostics/diagnostics_screen.dart';
import '../pet/companion_preview.dart';
import 'settings_widgets.dart';
import 'update_section.dart';

/// All user-facing preferences.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  bool? _notificationPermission;

  /// Set when the user asked for the companion but still has to grant the
  /// overlay permission on the system screen. Android gives us no callback for
  /// that screen, so the request is completed when the app comes back.
  bool _pendingPetEnable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_pendingPetEnable) return;
    _pendingPetEnable = false;
    _enablePet(context.read<SettingsController>());
  }

  Future<void> _refreshPermission() async {
    final service = context.read<NotificationService>();
    final granted = await service.hasPermission();
    if (mounted) setState(() => _notificationPermission = granted);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _togglePet(bool value, SettingsController settings) async {
    if (!value) {
      await context.read<PetPlatform>().hide();
      await settings.setPetEnabled(false);
      if (!mounted) return;
      _snack(context.tr('petDisabled'));
      return;
    }
    await _enablePet(settings);
  }

  /// Turn the companion on, granting the overlay permission first if needed.
  Future<void> _enablePet(SettingsController settings) async {
    final pet = context.read<PetPlatform>();
    final supported = await pet.isSupported();
    if (!mounted) return;
    if (!supported) {
      _snack(context.tr('petUnsupported'));
      return;
    }

    var granted = await pet.hasOverlayPermission();
    if (!granted) {
      await pet.requestOverlayPermission();
      // The system screen has no result; finish the job on resume instead of
      // telling the user to flip the switch a second time.
      _pendingPetEnable = true;
      if (!mounted) return;
      _snack(context.tr('petPermissionDenied'));
      return;
    }

    final current = settings.settings;
    final shown = await pet.show(
      scale: current.petScale,
      opacity: current.petOpacity,
      imagePath: current.petImagePath,
    );
    if (!mounted) return;
    if (!shown) {
      _snack(context.tr('petPermissionDenied'));
      return;
    }
    await settings.setPetEnabled(true);
    if (!mounted) return;
    _snack(context.tr('petEnabled'));
  }

  /// Copy the picked image into the app data directory.
  ///
  /// image_picker returns a path inside the system cache, which Android is free
  /// to delete; a companion that disappears after a reboot would look like a bug.
  Future<String?> _persistCompanionImage(String sourcePath) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final target = File('${dir.path}/companion${sourcePath.contains('.') ? sourcePath.substring(sourcePath.lastIndexOf('.')) : '.png'}');
      await File(sourcePath).copy(target.path);
      return target.path;
    } on Exception {
      return sourcePath;
    }
  }

  Future<void> _pickCompanionImage(SettingsController settings) async {
    final pet = context.read<PetPlatform>();
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final stored = await _persistCompanionImage(picked.path);
    await settings.setPetImagePath(stored);
    final current = settings.settings;
    if (current.petEnabled) {
      await pet.show(
        scale: current.petScale,
        opacity: current.petOpacity,
        imagePath: stored,
      );
    }
  }

  Future<void> _clearPasswords(DeviceController devices) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('settingsClearPasswordsTitle')),
        content: Text(context.tr('settingsClearPasswordsBody')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('no')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('yes')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await devices.clearAllPasswords();
    if (!mounted) return;
    _snack(context.tr('settingsClearPasswordsDone'));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final devices = context.watch<DeviceController>();
    final current = settings.settings;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settingsTitle'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          SettingsSectionHeader(title: context.tr('settingsAppearance')),
          ListTile(
            title: Text(context.tr('settingsTheme')),
            trailing: DropdownButton<ThemeMode>(
              value: current.themeMode,
              underline: const SizedBox.shrink(),
              onChanged: (mode) {
                if (mode != null) settings.setThemeMode(mode);
              },
              items: <DropdownMenuItem<ThemeMode>>[
                DropdownMenuItem<ThemeMode>(
                  value: ThemeMode.system,
                  child: Text(context.tr('themeSystem')),
                ),
                DropdownMenuItem<ThemeMode>(
                  value: ThemeMode.light,
                  child: Text(context.tr('themeLight')),
                ),
                DropdownMenuItem<ThemeMode>(
                  value: ThemeMode.dark,
                  child: Text(context.tr('themeDark')),
                ),
              ],
            ),
          ),
          ListTile(
            title: Text(context.tr('settingsLanguage')),
            trailing: DropdownButton<String>(
              value: current.localeCode ?? 'system',
              underline: const SizedBox.shrink(),
              onChanged: (code) {
                settings.setLocaleCode(code == null || code == 'system' ? null : code);
              },
              items: <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(
                  value: 'system',
                  child: Text(context.tr('languageSystem')),
                ),
                const DropdownMenuItem<String>(value: 'zh', child: Text('简体中文')),
                const DropdownMenuItem<String>(value: 'en', child: Text('English')),
              ],
            ),
          ),

          SettingsSectionHeader(title: context.tr('settingsNotifications')),
          SwitchListTile(
            title: Text(context.tr('settingsNotificationsEnabled')),
            subtitle: Text(context.tr('settingsNotificationsEnabledHint')),
            value: current.notificationsEnabled,
            onChanged: (value) async {
              if (value) {
                final granted = await context.read<NotificationService>().requestPermission();
                if (mounted) setState(() => _notificationPermission = granted);
              }
              await settings.setNotificationsEnabled(value);
            },
          ),
          SwitchListTile(
            title: Text(context.tr('settingsNotifyBackgroundOnly')),
            subtitle: Text(context.tr('settingsNotifyBackgroundOnlyHint')),
            value: current.notifyOnlyInBackground,
            onChanged: current.notificationsEnabled
                ? (value) => settings.setNotifyOnlyInBackground(value)
                : null,
          ),
          ListTile(
            title: Text(context.tr('settingsNotificationPermission')),
            subtitle: Text(
              _notificationPermission == null
                  ? ''
                  : context.tr(_notificationPermission!
                      ? 'settingsNotificationPermissionGranted'
                      : 'settingsNotificationPermissionDenied'),
            ),
            trailing: TextButton(
              onPressed: () async {
                final granted = await context.read<NotificationService>().requestPermission();
                if (mounted) setState(() => _notificationPermission = granted);
              },
              child: Text(context.tr('refresh')),
            ),
          ),

          SettingsSectionHeader(title: context.tr('settingsConnection')),
          SwitchListTile(
            title: Text(context.tr('settingsKeepAwake')),
            subtitle: Text(context.tr('settingsKeepAwakeHint')),
            value: current.keepScreenAwake,
            onChanged: settings.setKeepScreenAwake,
          ),
          SwitchListTile(
            title: Text(context.tr('settingsAutoReconnect')),
            subtitle: Text(context.tr('settingsAutoReconnectHint')),
            value: current.autoReconnect,
            onChanged: settings.setAutoReconnect,
          ),
          SwitchListTile(
            title: Text(context.tr('settingsAutoOpen')),
            value: current.autoOpenLastDevice,
            onChanged: settings.setAutoOpenLastDevice,
          ),

          SettingsSectionHeader(title: context.tr('settingsCompanion')),
          ListTile(
            leading: SizedBox(
              width: 56,
              height: 56,
              child: current.petImagePath == null
                  ? const CompanionPreview(size: 56)
                  : Image.file(File(current.petImagePath!), fit: BoxFit.contain),
            ),
            title: Text(context.tr('settingsPetEnabled')),
            subtitle: Text(context.tr('settingsPetEnabledHint')),
            trailing: Switch(
              value: current.petEnabled,
              onChanged: (value) => _togglePet(value, settings),
            ),
          ),
          ListTile(
            title: Text(context.tr('settingsPetPickImage')),
            trailing: const Icon(Icons.image_outlined),
            onTap: () => _pickCompanionImage(settings),
          ),
          if (current.petImagePath != null)
            ListTile(
              title: Text(context.tr('settingsPetResetImage')),
              trailing: const Icon(Icons.restart_alt),
              onTap: () => settings.setPetImagePath(null),
            ),
          ListTile(
            title: Text(context.tr('settingsPetScale')),
            subtitle: Slider(
              value: current.petScale,
              min: 0.5,
              max: 2.0,
              divisions: 6,
              label: current.petScale.toStringAsFixed(1),
              onChanged: settings.setPetScale,
              onChangeEnd: (value) async {
                if (settings.settings.petEnabled) {
                  await context.read<PetPlatform>().show(
                        scale: value,
                        opacity: settings.settings.petOpacity,
                        imagePath: settings.settings.petImagePath,
                      );
                }
              },
            ),
          ),
          ListTile(
            title: Text(context.tr('settingsPetOpacity')),
            subtitle: Slider(
              value: current.petOpacity,
              min: 0.3,
              max: 1.0,
              divisions: 7,
              label: current.petOpacity.toStringAsFixed(1),
              onChanged: settings.setPetOpacity,
              onChangeEnd: (value) async {
                if (settings.settings.petEnabled) {
                  await context.read<PetPlatform>().show(
                        scale: settings.settings.petScale,
                        opacity: value,
                        imagePath: settings.settings.petImagePath,
                      );
                }
              },
            ),
          ),

          SettingsSectionHeader(title: context.tr('settingsData')),
          ListTile(
            title: Text(context.tr('settingsExportHint')),
            subtitle: Text('${devices.devices.length}'),
          ),
          ListTile(
            title: Text(context.tr('settingsClearPasswords')),
            trailing: const Icon(Icons.lock_reset_outlined),
            onTap: () => _clearPasswords(devices),
          ),

          ListTile(
            leading: const Icon(Icons.monitor_heart_outlined),
            title: Text(context.tr('diagnosticsTitle')),
            subtitle: Text(context.tr('diagnosticsSettingsHint')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DiagnosticsScreen()),
            ),
          ),

          const UpdateSection(),

          SettingsSectionHeader(title: context.tr('aboutTitle')),
          ListTile(
            title: Text(context.tr('aboutCredits')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
