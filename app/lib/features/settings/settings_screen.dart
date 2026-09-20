import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/l10n.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/pet/pet_feature.dart';
import '../../core/state/device_controller.dart';
import '../../core/state/settings_controller.dart';
import '../about/about_screen.dart';
import '../diagnostics/diagnostics_screen.dart';
import '../pet/companion_settings.dart';
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
    // The notification permission can be granted from the system screen while
    // the app is in the background, so re-read it on the way back.
    if (state == AppLifecycleState.resumed) _refreshPermission();
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
            title: Text(context.tr('settingsSkipOnboarding')),
            subtitle: Text(context.tr('settingsSkipOnboardingHint')),
            value: current.skipDshOnboarding,
            onChanged: settings.setSkipDshOnboarding,
          ),
          SwitchListTile(
            title: Text(context.tr('settingsAutoOpen')),
            value: current.autoOpenLastDevice,
            onChanged: settings.setAutoOpenLastDevice,
          ),

          // The companion is on hold for now. The section still compiles and
          // is still analysed, it just is not offered; see PetFeature.available.
          if (PetFeature.available) const CompanionSettingsSection(),

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
