import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/dsh/dsh_endpoint.dart';
import '../../core/i18n/l10n.dart';
import '../../core/models/dsh_device.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/state/app_lifecycle.dart';
import '../../core/state/device_controller.dart';
import '../../core/state/settings_controller.dart';
import '../../core/state/update_controller.dart';
import '../browser/dsh_webview.dart';
import '../devices/device_edit_screen.dart';
import '../devices/device_list_screen.dart';
import '../devices/device_widgets.dart';
import '../scanner/scan_screen.dart';
import '../settings/settings_screen.dart';

/// The four-tab shell: scan, current device, device list, settings.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const int _tabDevice = 1;
  static const int _tabSettings = 3;

  int _index = _tabDevice;
  final GlobalKey<DshWebViewState> _webViewKey = GlobalKey<DshWebViewState>();
  String? _activePassword;
  String? _lastActiveId;
  DeviceController? _devices;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bind());
  }

  @override
  void dispose() {
    _devices?.removeListener(_onDevicesChanged);
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _bind() async {
    final devices = context.read<DeviceController>();
    _devices = devices;
    _lastActiveId = devices.activeDeviceId;
    devices.addListener(_onDevicesChanged);
    await _reloadPassword();
    await _applyWakelock();
    await _autoCheckUpdates();
  }

  /// One silent update check per launch.
  ///
  /// The app is distributed as an APK, not through a store, so nothing else
  /// would ever tell an installed copy that a newer one exists. Nothing is
  /// shown unless there really is a newer release.
  Future<void> _autoCheckUpdates() async {
    final settings = context.read<SettingsController>();
    if (!settings.settings.autoCheckUpdates) return;

    final updates = context.read<UpdateController>();
    final messenger = ScaffoldMessenger.of(context);
    final label = context.tr('settingsUpdateAvailable');
    final actionLabel = context.tr('settingsUpdate');

    final found = await updates.autoCheckOnce(prefer: settings.settings.updateSource);
    if (!found || !mounted) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text('$label ${updates.release?.version.core ?? ''}'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: actionLabel,
          onPressed: () {
            if (mounted) setState(() => _index = _tabSettings);
          },
        ),
      ),
    );
  }

  void _onDevicesChanged() {
    final devices = _devices;
    if (devices == null) return;
    final id = devices.activeDeviceId;
    if (id != _lastActiveId) {
      _lastActiveId = id;
      _reloadPassword();
    }
  }

  Future<void> _reloadPassword() async {
    final devices = _devices;
    if (devices == null) return;
    final id = devices.activeDeviceId;
    if (id == null) {
      if (mounted) setState(() => _activePassword = null);
      return;
    }
    final password = await devices.passwordFor(id);
    if (!mounted) return;
    setState(() => _activePassword = password);
  }

  bool? _wakelockOn;

  Future<void> _applyWakelock() async {
    final settings = context.read<SettingsController>().settings;
    _wakelockOn = null;
    _syncWakelock(wanted: settings.keepScreenAwake);
  }

  /// Idempotent: the platform is only touched when the desired state changes.
  void _syncWakelock({required bool wanted}) {
    if (_wakelockOn == wanted) return;
    _wakelockOn = wanted;
    if (wanted) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  Future<void> _selectDevice(DshDevice device) async {
    final devices = context.read<DeviceController>();
    final settings = context.read<SettingsController>();
    await devices.setActive(device.id);
    await settings.setActiveDeviceId(device.id);
    if (mounted) setState(() => _index = _tabDevice);
  }

  /// Add/edit dialog. `device == null` adds; [initialAddress] pre-fills a scan.
  Future<void> _openEditor({DshDevice? device, String? initialAddress, String? initialPassword}) async {
    final devices = context.read<DeviceController>();
    final settings = context.read<SettingsController>();
    final existingPassword =
        initialPassword ?? (device == null ? null : await devices.passwordFor(device.id));

    if (!mounted) return;
    final result = await Navigator.of(context).push<DeviceFormResult>(
      MaterialPageRoute<DeviceFormResult>(
        builder: (_) => DeviceEditScreen(
          device: device,
          initialAddress: initialAddress,
          initialPassword: existingPassword,
        ),
      ),
    );
    if (result == null || !mounted) return;

    if (device == null) {
      await devices.addFromEndpoint(
        result.endpoint,
        name: result.name,
        password: result.password,
      );
      await settings.setActiveDeviceId(devices.activeDeviceId);
      await _reloadPassword();
      if (mounted) {
        setState(() => _index = _tabDevice);
        _snack(context.tr('deviceAdded'));
      }
      return;
    }

    final failure = await devices.updateDevice(
      device.id,
      endpoint: result.endpoint,
      name: result.name,
      password: result.password,
      passwordChanged: result.passwordChanged,
    );
    await _reloadPassword();
    if (!mounted) return;
    _snack(failure != null ? context.tr('passwordSaveFailed') : context.tr('deviceUpdated'));
  }

  Future<void> _deleteDevice(DshDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('deleteDeviceTitle')),
        content: Text(context.tr('deleteDeviceBody')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final devices = context.read<DeviceController>();
    final settings = context.read<SettingsController>();
    await devices.remove(device.id);
    await settings.setActiveDeviceId(devices.activeDeviceId);
    await _reloadPassword();
  }

  /// A scanned QR code.
  ///
  /// dsh-pocket's QR payload is a bare URL, so most scans need the PIN typed
  /// once — we open the editor for that. A share link that already carries
  /// `?token=` is added silently.
  Future<void> _onScanned(DshEndpoint endpoint) async {
    if (endpoint.password != null && endpoint.password!.isNotEmpty) {
      final devices = context.read<DeviceController>();
      final settings = context.read<SettingsController>();
      await devices.addFromEndpoint(endpoint, password: endpoint.password);
      await settings.setActiveDeviceId(devices.activeDeviceId);
      await _reloadPassword();
      if (!mounted) return;
      setState(() => _index = _tabDevice);
      _snack(context.tr('deviceAdded'));
      return;
    }
    await _openEditor(initialAddress: endpoint.baseUrl);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final devices = context.watch<DeviceController>();
    final active = devices.activeDevice;
    final settings = context.watch<SettingsController>();

    // Keep the screen awake only while a session is actually on screen.
    // Applied here (rather than in a listener) because the condition depends on
    // the selected tab as well; _syncWakelock makes the call idempotent so a
    // rebuild does not hammer the platform channel.
    _syncWakelock(
      wanted: settings.settings.keepScreenAwake && _index == _tabDevice && active != null,
    );

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          // The camera is only alive while its tab is selected.
          _index == 0
              ? ScanScreen(
                  onScanned: _onScanned,
                  onManualEntry: () => _openEditor(),
                )
              : const SizedBox.shrink(),
          _DeviceTab(
            webViewKey: _webViewKey,
            device: active,
            password: _activePassword,
            onChooseDevice: () => setState(() => _index = 2),
            onAddDevice: () => _openEditor(),
            onEditDevice: (device) => _openEditor(device: device),
          ),
          DeviceListScreen(
            onSelect: _selectDevice,
            onAdd: () => _openEditor(),
            onEdit: (device) => _openEditor(device: device),
            onDelete: _deleteDevice,
          ),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: <Widget>[
          NavigationDestination(
            icon: const Icon(Icons.qr_code_scanner),
            label: context.tr('tabScan'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.smartphone_outlined),
            selectedIcon: const Icon(Icons.smartphone),
            label: _navDeviceLabel(active, devices),
          ),
          NavigationDestination(
            icon: const Icon(Icons.list_alt_outlined),
            selectedIcon: const Icon(Icons.list_alt),
            label: context.tr('tabDevices'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: context.tr('tabSettings'),
          ),
        ],
      ),
    );
  }

  /// The tab is labelled with the device nickname, which is what the user
  /// asked for: the device name lives in the navigation bar.
  String _navDeviceLabel(DshDevice? device, DeviceController devices) {
    if (device == null) return context.tr('tabDevice');
    final name = device.name;
    return name.length <= 8 ? name : '${name.substring(0, 7)}…';
  }
}

/// The "current device" tab: either the WebView or a call to action.
class _DeviceTab extends StatelessWidget {
  const _DeviceTab({
    required this.webViewKey,
    required this.device,
    required this.password,
    required this.onChooseDevice,
    required this.onAddDevice,
    required this.onEditDevice,
  });

  final GlobalKey<DshWebViewState> webViewKey;
  final DshDevice? device;
  final String? password;
  final VoidCallback onChooseDevice;
  final VoidCallback onAddDevice;
  final ValueChanged<DshDevice> onEditDevice;

  @override
  Widget build(BuildContext context) {
    final current = device;
    if (current == null) {
      return _NoDeviceView(onChooseDevice: onChooseDevice, onAddDevice: onAddDevice);
    }
    final settings = context.watch<SettingsController>().settings;
    final lifecycle = context.read<AppLifecycleObserver>();
    final notifications = context.read<NotificationService>();
    final devices = context.read<DeviceController>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: <Widget>[
            Flexible(child: Text(current.name, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            DeviceKindChip(kind: current.kind),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: context.tr('refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: () => webViewKey.currentState?.reload(),
          ),
          IconButton(
            tooltip: context.tr('openDeviceList'),
            icon: const Icon(Icons.devices_other_outlined),
            onPressed: onChooseDevice,
          ),
          IconButton(
            tooltip: context.tr('editDeviceTitle'),
            icon: const Icon(Icons.tune),
            onPressed: () => onEditDevice(current),
          ),
        ],
      ),
      body: DshWebView(
        key: webViewKey,
        device: current,
        password: password,
        settings: settings,
        lifecycle: lifecycle,
        notificationService: notifications,
        onPasswordEntered: (entered) async {
          final failure = await devices.setPassword(current.id, entered);
          if (failure != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.tr('passwordSaveFailed'))),
            );
          }
        },
      ),
    );
  }
}

class _NoDeviceView extends StatelessWidget {
  const _NoDeviceView({required this.onChooseDevice, required this.onAddDevice});

  final VoidCallback onChooseDevice;
  final VoidCallback onAddDevice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDevices = context.watch<DeviceController>().devices.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.link_off, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(context.tr('currentDeviceNone'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 24),
            if (hasDevices)
              FilledButton.icon(
                onPressed: onChooseDevice,
                icon: const Icon(Icons.list_alt),
                label: Text(context.tr('openDeviceList')),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onAddDevice,
              icon: const Icon(Icons.add),
              label: Text(context.tr('addDevice')),
            ),
          ],
        ),
      ),
    );
  }
}
