import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/l10n.dart';
import '../../core/models/dsh_device.dart';
import '../../core/state/device_controller.dart';
import 'device_widgets.dart';

/// The saved-device list: connect, rename, edit, delete.
class DeviceListScreen extends StatelessWidget {
  const DeviceListScreen({
    required this.onSelect,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final ValueChanged<DshDevice> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<DshDevice> onEdit;
  final ValueChanged<DshDevice> onDelete;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DeviceController>();
    final devices = controller.devices;

    if (devices.isEmpty) {
      return _EmptyState(onAdd: onAdd);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('tabDevices')),
        actions: <Widget>[
          IconButton(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            tooltip: context.tr('addDevice'),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: devices.length,
        separatorBuilder: (_, __) => const SizedBox(height: 0),
        itemBuilder: (context, index) {
          final device = devices[index];
          final isActive = device.id == controller.activeDeviceId;
          return _DeviceTile(
            device: device,
            isActive: isActive,
            onTap: () => onSelect(device),
            onEdit: () => onEdit(device),
            onDelete: () => onDelete(device),
          );
        },
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.isActive,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final DshDevice device;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastConnected = relativeTime(context, device.lastConnectedAt);
    return ListTile(
      selected: isActive,
      leading: CircleAvatar(
        backgroundColor: isActive
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          device.kind == DshAccessKind.tunnel ? Icons.public : Icons.computer_outlined,
          color: isActive ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: Row(
        children: <Widget>[
          Flexible(child: Text(device.name, overflow: TextOverflow.ellipsis)),
          if (device.hasPassword) ...<Widget>[
            const SizedBox(width: 6),
            Icon(Icons.lock_outline, size: 14, color: theme.colorScheme.outline),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: <Widget>[
            DeviceKindChip(kind: device.kind),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                device.address,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (lastConnected.isNotEmpty) ...<Widget>[
              const SizedBox(width: 8),
              Text('· $lastConnected', style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'edit') onEdit();
          if (value == 'delete') onDelete();
        },
        itemBuilder: (context) => <PopupMenuEntry<String>>[
          PopupMenuItem<String>(value: 'edit', child: Text(context.tr('editDeviceTitle'))),
          PopupMenuItem<String>(value: 'delete', child: Text(context.tr('delete'))),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.devices_other_outlined, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(context.tr('noDeviceTitle'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              context.tr('noDeviceBody'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(context.tr('addDevice')),
            ),
          ],
        ),
      ),
    );
  }
}
