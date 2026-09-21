import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/l10n.dart';
import '../../core/state/settings_controller.dart';
import '../../core/state/update_controller.dart';
import '../../core/update/release_channels.dart';
import 'settings_widgets.dart';

/// The "Updates" block: installed version, release channel, and the whole
/// check → download → hand-to-installer flow.
///
/// The app is distributed as an APK rather than through a store, so this is the
/// only way an installed copy ever learns that a newer one exists.
class UpdateSection extends StatelessWidget {
  const UpdateSection({super.key});

  @override
  Widget build(BuildContext context) {
    final update = context.watch<UpdateController>();
    final settings = context.watch<SettingsController>();
    final current = settings.settings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SettingsSectionHeader(title: context.tr('settingsUpdate')),
        ListTile(
          title: Text(context.tr('settingsUpdateCurrent')),
          trailing: Text(
            update.currentVersion.isEmpty ? '—' : update.currentVersion,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        SwitchListTile(
          title: Text(context.tr('settingsUpdateAuto')),
          value: current.autoCheckUpdates,
          onChanged: settings.setAutoCheckUpdates,
        ),
        ListTile(
          title: Text(context.tr('settingsUpdateSource')),
          subtitle: Text(_sourceLabel(context, current.updateSource)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pickSource(context, settings, current.updateSource),
        ),
        ListTile(
          title: Text(context.tr('settingsUpdateCheck')),
          subtitle: Text(_statusText(context, update)),
          trailing: update.phase == UpdatePhase.checking
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.system_update_alt),
          onTap: update.phase == UpdatePhase.checking || update.phase == UpdatePhase.downloading
              ? null
              : () => update.check(prefer: current.updateSource),
        ),
        ..._details(context, update),
      ],
    );
  }

  String _sourceLabel(BuildContext context, UpdateSourcePreference preference) {
    return switch (preference) {
      UpdateSourcePreference.auto => context.tr('settingsUpdateSourceAuto'),
      UpdateSourcePreference.github => context.tr('settingsUpdateSourceGithub'),
      UpdateSourcePreference.gitee => context.tr('settingsUpdateSourceGitee'),
    };
  }

  String _statusText(BuildContext context, UpdateController update) {
    return switch (update.phase) {
      UpdatePhase.idle => '',
      UpdatePhase.checking => context.tr('settingsUpdateChecking'),
      UpdatePhase.upToDate => context.tr('settingsUpdateUpToDate'),
      UpdatePhase.available => context.tr('settingsUpdateAvailable'),
      UpdatePhase.downloading => context.tr('settingsUpdateDownloading'),
      UpdatePhase.needsPermission => context.tr('settingsUpdateNeedsPermission'),
      UpdatePhase.signatureMismatch => context.tr('settingsUpdateSignatureMismatch'),
      UpdatePhase.ready => context.tr('settingsUpdateReady'),
      UpdatePhase.error => switch (update.error) {
          null || 'noApk' => context.tr('settingsUpdateUnreachable'),
          'notPublished' => context.tr('settingsUpdateNotPublished'),
          _ => context.tr('settingsUpdateFailed'),
        },
    };
  }

  /// A dialog rather than a dropdown: the labels are long enough to overflow a
  /// trailing dropdown on a narrow phone.
  Future<void> _pickSource(
    BuildContext context,
    SettingsController settings,
    UpdateSourcePreference selected,
  ) async {
    final chosen = await showDialog<UpdateSourcePreference>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.tr('settingsUpdateSource')),
        children: <Widget>[
          // RadioGroup owns the selection since Flutter 3.32; passing
          // groupValue/onChanged to each tile is deprecated.
          RadioGroup<UpdateSourcePreference>(
            groupValue: selected,
            onChanged: (value) => Navigator.of(context).pop(value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final preference in UpdateSourcePreference.values)
                  RadioListTile<UpdateSourcePreference>(
                    value: preference,
                    title: Text(_sourceLabel(context, preference)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (chosen != null) await settings.setUpdateSource(chosen);
  }

  List<Widget> _details(BuildContext context, UpdateController update) {
    final theme = Theme.of(context);
    final release = update.release;

    switch (update.phase) {
      case UpdatePhase.downloading:
        final progress = update.progress;
        return <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 6),
                Text(
                  progress == null
                      ? context.tr('settingsUpdateDownloading')
                      : '${(progress * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ];

      case UpdatePhase.needsPermission:
        return <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(context.tr('settingsUpdateNeedsPermission')),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: update.installDownloaded,
                  child: Text(context.tr('settingsUpdateContinue')),
                ),
              ],
            ),
          ),
        ];

      case UpdatePhase.ready:
        return <Widget>[
          ListTile(
            leading: Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
            title: Text(context.tr('settingsUpdateReady')),
          ),
        ];

      case UpdatePhase.error:
        // 'notPublished' is a diagnosis, not a failure detail: the hosts
        // answered, they simply have nothing to offer yet. Showing the raw
        // "GitHub: HTTP 404 / Gitee: HTTP 404" would leave the user to
        // decode that themselves.
        final notPublished = update.error == 'notPublished';
        return <Widget>[
          ListTile(
            leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
            title: Text(update.error == 'noApk'
                ? context.tr('settingsUpdateNoApk')
                : notPublished
                    ? context.tr('settingsUpdateNotPublished')
                    : context.tr('settingsUpdateFailed')),
            subtitle: update.error == null || update.error == 'noApk'
                ? null
                : Text(
                    notPublished
                        ? context.tr('settingsUpdateNotPublishedHint')
                        : update.error!,
                    style: theme.textTheme.bodySmall,
                  ),
            trailing: TextButton(
              onPressed: () => update.check(
                prefer: context.read<SettingsController>().settings.updateSource,
              ),
              child: Text(context.tr('settingsUpdateRetry')),
            ),
          ),
        ];

      case UpdatePhase.available:
        if (release == null) return const <Widget>[];
        return <Widget>[
          ListTile(
            leading: Icon(Icons.new_releases_outlined, color: theme.colorScheme.primary),
            title: Text('${context.tr('settingsUpdateAvailable')} ${release.version.core}'),
            subtitle: Text('${context.tr('settingsUpdateFrom')} ${release.source.label}'),
          ),
          if (release.notes != null)
            ExpansionTile(
              title: Text(context.tr('settingsUpdateNotes')),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SelectableText(release.notes!, style: theme.textTheme.bodySmall),
              ],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: FilledButton.icon(
              onPressed: release.hasApk ? update.downloadAndInstall : null,
              icon: const Icon(Icons.download_outlined),
              label: Text(
                context.tr(release.hasApk ? 'settingsUpdateInstall' : 'settingsUpdateNoApk'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              context.tr('settingsUpdateSignatureHint'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
        ];

      // A dead end unless the user is told two things: why Android refuses,
      // and where the file is. Uninstalling deletes our cache, so the copy in
      // Downloads is the only thing that makes the instruction followable.
      case UpdatePhase.signatureMismatch:
        final saved = update.savedApkName;
        return <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.tr('settingsUpdateSignatureMismatch'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  saved == null
                      ? context.tr('settingsUpdateSignatureNoCopy')
                      : '${context.tr('settingsUpdateSignatureSaved')} $saved',
                  style: theme.textTheme.bodySmall,
                ),
                if (saved == null) ...<Widget>[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: update.shareDownloadedApk,
                    icon: const Icon(Icons.share_outlined),
                    label: Text(context.tr('settingsUpdateShareApk')),
                  ),
                ],
              ],
            ),
          ),
        ];

      case UpdatePhase.idle:
      case UpdatePhase.checking:
      case UpdatePhase.upToDate:
        return const <Widget>[];
    }
  }
}
