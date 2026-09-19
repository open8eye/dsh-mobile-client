import 'package:flutter/material.dart';

import '../../core/i18n/l10n.dart';
import '../../core/models/dsh_device.dart';

/// Small badge telling the user how the device is reached.
///
/// This mirrors the server's own host classification, so "局域网" really does
/// mean "the LAN PIN applies" and "Tailscale" really does mean "the same PIN,
/// over your tailnet".
class DeviceKindChip extends StatelessWidget {
  const DeviceKindChip({required this.kind, super.key});

  final DshAccessKind kind;

  String _label(BuildContext context) {
    switch (kind) {
      case DshAccessKind.lan:
        return context.tr('deviceKindLan');
      case DshAccessKind.tailscale:
        return context.tr('deviceKindTailscale');
      case DshAccessKind.tunnel:
        return context.tr('deviceKindTunnel');
      case DshAccessKind.custom:
        return context.tr('deviceKindCustom');
    }
  }

  IconData get _icon {
    switch (kind) {
      case DshAccessKind.lan:
        return Icons.wifi;
      case DshAccessKind.tailscale:
        return Icons.vpn_lock_outlined;
      case DshAccessKind.tunnel:
        return Icons.public;
      case DshAccessKind.custom:
        return Icons.dns_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_icon, size: 12, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            _label(context),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// Formats "last connected" without pulling in a date-formatting package.
String relativeTime(BuildContext context, DateTime? value) {
  if (value == null) return '';
  final delta = DateTime.now().difference(value);
  final isZh = L10nScope.of(context).code == 'zh';
  if (delta.inMinutes < 1) return isZh ? '刚刚' : 'just now';
  if (delta.inHours < 1) {
    return isZh ? '${delta.inMinutes} 分钟前' : '${delta.inMinutes} min ago';
  }
  if (delta.inDays < 1) {
    return isZh ? '${delta.inHours} 小时前' : '${delta.inHours} h ago';
  }
  return isZh ? '${delta.inDays} 天前' : '${delta.inDays} d ago';
}
