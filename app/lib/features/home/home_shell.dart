import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/dsh/dsh_endpoint.dart';
import '../../core/i18n/l10n.dart';
import '../../core/models/dsh_device.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/state/app_lifecycle.dart';
import '../../core/state/device_controller.dart';
import '../../core/state/session_set.dart';
import '../../core/state/settings_controller.dart';
import '../../core/state/update_controller.dart';
import '../browser/dsh_webview.dart';
import '../devices/device_edit_screen.dart';
import '../devices/device_list_screen.dart';
import '../devices/device_widgets.dart';
import '../scanner/scan_screen.dart';
import '../settings/settings_screen.dart';

/// The shell: a stack of live sessions, with a bar of icons underneath.
///
/// The bar has six slots but only four of them are pages. The other two are
/// actions — switching between sessions and reloading the current one — which
/// is why there is no longer an AppBar above the WebView to hold them.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// Pages in the [IndexedStack]. The bar's six slots map onto these.
  static const int _pageScan = 0;
  static const int _pageSession = 1;
  static const int _pageDevices = 2;
  static const int _pageSettings = 3;

  /// How many sessions stay alive at once.
  ///
  /// Every live WebView keeps a Chromium renderer resident — tens of megabytes
  /// each. On the old devices this app exists for, a handful is enough to get
  /// the process killed, so the least recently used one is dropped.
  static const int _maxSessions = 4;

  int _page = _pageSession;

  /// Which sessions are alive, and which one is on screen.
  final SessionSet _sessions = SessionSet(maxSessions: _maxSessions);

  /// One key per session, created when it opens and dropped when it closes.
  final Map<String, GlobalKey<DshWebViewState>> _keys =
      <String, GlobalKey<DshWebViewState>>{};

  /// Passwords read from the keystore, so a rebuild does not re-read them.
  final Map<String, String?> _passwords = <String, String?>{};

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
    devices.addListener(_onDevicesChanged);

    // Opening straight into the last-used device is the whole point of the
    // app; the session count starting at 1 is the honest consequence.
    final active = devices.activeDevice;
    if (active != null) {
      await _openSession(active, switchTo: false);
    }
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
            if (mounted) setState(() => _page = _pageSettings);
          },
        ),
      ),
    );
  }

  /// A device that no longer exists cannot keep a session: its WebView would be
  /// pointed at an entry the user has deleted.
  void _onDevicesChanged() {
    final devices = _devices;
    if (devices == null) return;
    final keep = devices.devices.map((device) => device.id).toSet();
    if (_sessions.ids.every(keep.contains)) return;
    // This fires from inside notifyListeners(), which can be mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _forget(_sessions.retain(keep)));
    });
  }

  /// Last state pushed to the platform, so a rebuild does not repeat the call.
  bool? _wakelockOn;

  /// Idempotent: the platform is only touched when the desired state changes.
  ///
  /// Driven from [build] rather than set here, because whether the screen
  /// should stay awake depends on which page is showing, not just on the
  /// setting.
  void _syncWakelock({required bool wanted}) {
    if (_wakelockOn == wanted) return;
    _wakelockOn = wanted;
    if (wanted) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  /// Bring a device up as a live session and make it the one on screen.
  Future<void> _openSession(DshDevice device, {bool switchTo = true}) async {
    final devices = context.read<DeviceController>();
    final settings = context.read<SettingsController>();

    // Read the password *before* the WebView exists. A session that starts
    // without it lands on the login page and asks for a PIN that is already in
    // the keystore.
    final password = await devices.passwordFor(device.id);
    if (!mounted) return;

    setState(() {
      final dropped = _sessions.open(device.id);
      _keys.putIfAbsent(device.id, () => GlobalKey<DshWebViewState>());
      _passwords[device.id] = password;
      _forget(dropped);
      if (switchTo) _page = _pageSession;
    });

    await devices.setActive(device.id);
    await settings.setActiveDeviceId(device.id);
  }

  /// Drop the bookkeeping for sessions that are no longer alive.
  void _forget(List<String> ids) {
    for (final id in ids) {
      _keys.remove(id);
      _passwords.remove(id);
    }
  }

  /// Make an already-open session current, and show it.
  void _activateSession(String id) {
    setState(() {
      if (_sessions.activate(id)) _page = _pageSession;
    });
    context.read<DeviceController>().setActive(_sessions.currentId);
  }

  /// Drop a session and let its WebView go.
  void _closeSession(String id) {
    setState(() {
      if (_sessions.close(id)) _forget(<String>[id]);
    });
    context.read<DeviceController>().setActive(_sessions.currentId);
  }

  Future<void> _rememberPassword(String deviceId, String password) async {
    final devices = context.read<DeviceController>();
    final failure = await devices.setPassword(deviceId, password);
    if (!mounted) return;
    if (failure != null) {
      _snack(context.tr('passwordSaveFailed'));
      return;
    }
    setState(() => _passwords[deviceId] = password);
  }

  Future<void> _reloadCurrent() async {
    final id = _sessions.currentId;
    if (id == null) return;
    await _keys[id]?.currentState?.reload();
  }

  /// The session picker: who is open, and which one is on screen.
  Future<void> _showSessions() async {
    final devices = context.read<DeviceController>();
    final live = <DshDevice>[
      for (final id in _sessions.ids.reversed)
        if (devices.byId(id) case final DshDevice device) device,
    ];
    if (live.isEmpty) return;

    final action = await showModalBottomSheet<_SessionAction>(
      context: context,
      showDragHandle: true,
      builder: (_) => _SessionSheet(
        devices: live,
        currentId: _sessions.currentId,
      ),
    );
    if (action == null || !mounted) return;
    if (action.close) {
      _closeSession(action.id);
    } else {
      _activateSession(action.id);
    }
  }

  Future<void> _openCurrentConfig() async {
    final id = _sessions.currentId;
    final device = id == null ? null : context.read<DeviceController>().byId(id);
    if (device == null) {
      setState(() => _page = _pageDevices);
      return;
    }
    await _openEditor(device: device);
  }

  /// Add/edit dialog. `device == null` adds; [initialAddress] pre-fills a scan.
  ///
  /// The form has no password field, so nothing here reads the keystore: the
  /// screen only needs to know *whether* a password is stored, which
  /// [DshDevice.hasPassword] already records. The secret itself stays with the
  /// prompt that captured it.
  Future<void> _openEditor({DshDevice? device, String? initialAddress}) async {
    final devices = context.read<DeviceController>();
    final result = await Navigator.of(context).push<DeviceFormResult>(
      MaterialPageRoute<DeviceFormResult>(
        builder: (_) => DeviceEditScreen(
          device: device,
          initialAddress: initialAddress,
        ),
      ),
    );
    if (result == null || !mounted) return;

    if (device == null) {
      // A scan that carried `?token=` never reaches this form; it is added
      // with its password already in hand by _onScanned.
      final added = await devices.addFromEndpoint(result.endpoint, name: result.name);
      if (!mounted) return;
      await _openSession(added);
      if (mounted) _snack(context.tr('deviceAdded'));
      return;
    }

    await devices.updateDevice(device.id, endpoint: result.endpoint, name: result.name);
    if (result.clearPassword) {
      // After updateDevice, so the record it just wrote cannot put the flag
      // back. The live session rebuilds with no password and lands on the
      // login page, which is what clearing it is supposed to do.
      await devices.setPassword(device.id, null);
      if (!mounted) return;
      setState(() => _passwords[device.id] = null);
      _snack(context.tr('passwordCleared'));
      return;
    }
    if (!mounted) return;
    _snack(context.tr('deviceUpdated'));
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
    await devices.remove(device.id);
    if (!mounted) return;
    // remove() already repointed activeDeviceId; keep the live set in step.
    _closeSession(device.id);
  }

  /// A scanned QR code.
  ///
  /// dsh-pocket's QR payload is a bare URL, so most scans need the PIN typed
  /// once — we open the editor for that. A share link that already carries
  /// `?token=` is added silently.
  Future<void> _onScanned(DshEndpoint endpoint) async {
    if (endpoint.password != null && endpoint.password!.isNotEmpty) {
      final devices = context.read<DeviceController>();
      final added = await devices.addFromEndpoint(endpoint, password: endpoint.password);
      if (!mounted) return;
      await _openSession(added);
      if (mounted) _snack(context.tr('deviceAdded'));
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
    final settings = context.watch<SettingsController>();
    final currentId = _sessions.currentId;
    final current = currentId == null ? null : devices.byId(currentId);

    // Keep the screen awake only while a session is actually on screen.
    // Applied here (rather than in a listener) because the condition depends on
    // the selected page as well; _syncWakelock makes the call idempotent so a
    // rebuild does not hammer the platform channel.
    _syncWakelock(
      wanted: settings.settings.keepScreenAwake &&
          _page == _pageSession &&
          current != null,
    );

    return Scaffold(
      body: IndexedStack(
        index: _page,
        sizing: StackFit.expand,
        children: <Widget>[
          // The camera is only alive while its page is selected.
          _page == _pageScan
              ? ScanScreen(
                  onScanned: _onScanned,
                  onManualEntry: () => _openEditor(),
                )
              : const SizedBox.shrink(),
          // No AppBar above the WebView, so the status bar has to be kept out
          // of it here instead.
          SafeArea(
            bottom: false,
            child: _buildSessions(devices, settings),
          ),
          DeviceListScreen(
            onSelect: _openSession,
            onAdd: () => _openEditor(),
            onEdit: (device) => _openEditor(device: device),
            onDelete: _deleteDevice,
          ),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        page: _page,
        sessionCount: _sessions.length,
        currentName: current?.name,
        onScan: () => setState(() => _page = _pageScan),
        onSessions: _showSessions,
        onCurrentDevice: _openCurrentConfig,
        onDevices: () => setState(() => _page = _pageDevices),
        onSettings: () => setState(() => _page = _pageSettings),
        onRefresh: current == null ? null : _reloadCurrent,
      ),
    );
  }

  Widget _buildSessions(DeviceController devices, SettingsController settings) {
    final live = <DshDevice>[
      for (final id in _sessions.ids)
        if (devices.byId(id) case final DshDevice device) device,
    ];
    if (live.isEmpty) {
      return _NoDeviceView(
        onChooseDevice: () => setState(() => _page = _pageDevices),
        onAddDevice: () => _openEditor(),
      );
    }

    final lifecycle = context.read<AppLifecycleObserver>();
    final notifications = context.read<NotificationService>();
    final index = live.indexWhere((device) => device.id == _sessions.currentId);

    return IndexedStack(
      index: index < 0 ? live.length - 1 : index,
      sizing: StackFit.expand,
      children: <Widget>[
        for (final device in live)
          DshWebView(
            key: _keys[device.id],
            device: device,
            password: _passwords[device.id],
            settings: settings.settings,
            lifecycle: lifecycle,
            notificationService: notifications,
            isActive: device.id == _sessions.currentId,
            onPasswordEntered: (entered) => _rememberPassword(device.id, entered),
          ),
      ],
    );
  }
}

/// What the session sheet was asked to do.
class _SessionAction {
  const _SessionAction(this.id, {this.close = false});

  final String id;
  final bool close;
}

class _SessionSheet extends StatelessWidget {
  const _SessionSheet({required this.devices, required this.currentId});

  final List<DshDevice> devices;
  final String? currentId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            child: Text(
              context.tr('sessionsTitle'),
              style: theme.textTheme.titleMedium,
            ),
          ),
          for (final device in devices)
            ListTile(
              leading: Icon(
                device.id == currentId ? Icons.play_circle : Icons.circle_outlined,
                color: device.id == currentId
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              title: Text(device.name, overflow: TextOverflow.ellipsis),
              subtitle: Align(
                alignment: Alignment.centerLeft,
                child: DeviceKindChip(kind: device.kind),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                tooltip: context.tr('sessionClose'),
                onPressed: () =>
                    Navigator.of(context).pop(_SessionAction(device.id, close: true)),
              ),
              onTap: () => Navigator.of(context).pop(_SessionAction(device.id)),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// The six-slot bar: four pages, one picker, one reload.
///
/// Icons only — the labels live in tooltips and semantics, which is also what
/// keeps the row narrow enough for six slots on a small phone.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.page,
    required this.sessionCount,
    required this.currentName,
    required this.onScan,
    required this.onSessions,
    required this.onCurrentDevice,
    required this.onDevices,
    required this.onSettings,
    required this.onRefresh,
  });

  /// The name slot is a fixed width so that a long nickname cannot stretch the
  /// bar and shift every icon next to it.
  static const double _nameWidth = 88;

  /// Floor for the five icon slots, so a narrow phone shrinks the name before
  /// it squeezes an icon into an overflow.
  static const double _iconSlot = 40;

  final int page;
  final int sessionCount;
  final String? currentName;
  final VoidCallback onScan;
  final VoidCallback onSessions;
  final VoidCallback onCurrentDevice;
  final VoidCallback onDevices;
  final VoidCallback onSettings;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Six slots on a 320dp phone: 96 for the name would leave the
              // icons less room than they need, so the name gives way first.
              final room = constraints.maxWidth - _iconSlot * 5;
              final nameWidth = math.max(_iconSlot, math.min(_nameWidth, room));
              return Row(
                children: <Widget>[
                  _BarAction(
                    icon: Icons.qr_code_scanner,
                    tooltip: context.tr('tabScan'),
                    selected: page == 0,
                    onTap: onScan,
                  ),
                  _BarAction(
                    icon: Icons.layers_outlined,
                    selectedIcon: Icons.layers,
                    tooltip: context.tr('navSessions'),
                    selected: page == 1,
                    badge: sessionCount,
                    onTap: onSessions,
                  ),
                  SizedBox(
                    width: nameWidth,
                    child: _NameSlot(
                      name: currentName,
                      tooltip: currentName == null
                          ? context.tr('openDeviceList')
                          : context.tr('editDeviceTitle'),
                      onTap: onCurrentDevice,
                    ),
                  ),
                  _BarAction(
                    icon: Icons.list_alt_outlined,
                    selectedIcon: Icons.list_alt,
                    tooltip: context.tr('tabDevices'),
                    selected: page == 2,
                    onTap: onDevices,
                  ),
                  _BarAction(
                    icon: Icons.settings_outlined,
                    selectedIcon: Icons.settings,
                    tooltip: context.tr('tabSettings'),
                    selected: page == 3,
                    onTap: onSettings,
                  ),
                  _BarAction(
                    icon: Icons.refresh,
                    tooltip: context.tr('refresh'),
                    onTap: onRefresh,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BarAction extends StatelessWidget {
  const _BarAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selectedIcon,
    this.selected = false,
    this.badge,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool selected;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    final Color color;
    if (!enabled) {
      color = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.38);
    } else if (selected) {
      color = theme.colorScheme.onSecondaryContainer;
    } else {
      color = theme.colorScheme.onSurfaceVariant;
    }

    Widget iconWidget = Icon(
      selected && selectedIcon != null ? selectedIcon : icon,
      color: color,
    );
    final count = badge;
    if (count != null && count > 0) {
      iconWidget = Badge.count(count: count, child: iconWidget);
    }

    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: InkResponse(
          onTap: onTap,
          radius: 30,
          child: Center(
            // A fixed box rather than padding: the indicator must never be
            // wider than the slot it sits in, or six of them overflow.
            child: Container(
              width: 40,
              height: 32,
              alignment: Alignment.center,
              decoration: selected
                  ? BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    )
                  : null,
              child: iconWidget,
            ),
          ),
        ),
      ),
    );
  }
}

/// The device name, in the middle of the bar. Tapping it opens that device's
/// settings — which is where the kind chip went when the AppBar was removed.
class _NameSlot extends StatelessWidget {
  const _NameSlot({required this.name, required this.tooltip, required this.onTap});

  final String? name;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = name ?? context.tr('tabDevice');
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(
              color: name == null
                  ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
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
