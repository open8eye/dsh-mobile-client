import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/diagnostics/diagnostics.dart';
import '../../core/diagnostics/diagnostics_report.dart';
import '../../core/diagnostics/log_entry.dart';
import '../../core/i18n/l10n.dart';
import '../../core/platform/app_platform.dart';
import '../../core/update/release_channels.dart';
import '../settings/settings_widgets.dart';

/// "Something is wrong" → "here is what to send me".
///
/// There is no analytics and no crash reporting in this app, by design. That
/// makes this screen the entire feedback channel: it has to show the user what
/// will be sent, let them read it, and get it off the phone through the one
/// mechanism every Android device has — the share sheet.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  Map<String, String> _deviceInfo = const <String, String>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await DiagnosticsReport.deviceInfo(refresh: true);
    if (!mounted) return;
    setState(() {
      _deviceInfo = info;
      _loading = false;
    });
  }

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final copied = context.tr('diagnosticsCopied');
    final failed = context.tr('diagnosticsCopyFailed');
    try {
      final report = await DiagnosticsReport.build();
      await Clipboard.setData(ClipboardData(text: report));
      messenger.showSnackBar(SnackBar(content: Text(copied)));
    } on Exception {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  Future<void> _share(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.tr('diagnosticsShareFailed');
    try {
      final report = await DiagnosticsReport.build();
      final subject = await DiagnosticsReport.subject();
      final ok = await AppPlatform.shareText(text: report, subject: subject);
      if (!ok) messenger.showSnackBar(SnackBar(content: Text(failed)));
    } on Exception {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  Future<void> _clear(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final done = context.tr('diagnosticsCleared');
    await Diagnostics.instance.clear();
    messenger.showSnackBar(SnackBar(content: Text(done)));
  }

  Future<void> _openIssues() async {
    final uri = Uri.parse('https://github.com/${ReleaseChannels.githubRepo}/issues');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Exception {
      // No browser: nothing else to try.
    }
  }

  @override
  Widget build(BuildContext context) {
    final diagnostics = Diagnostics.instance;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('diagnosticsTitle')),
        actions: <Widget>[
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: context.tr('refresh'),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: diagnostics,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(Icons.lock_outline, size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.tr('diagnosticsIntro'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _copy(context),
                      icon: const Icon(Icons.copy_all_outlined),
                      label: Text(context.tr('diagnosticsCopy')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _share(context),
                      icon: const Icon(Icons.ios_share),
                      label: Text(context.tr('diagnosticsShare')),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _openIssues,
                      icon: const Icon(Icons.bug_report_outlined),
                      label: Text(context.tr('diagnosticsOpenIssue')),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _clear(context),
                      icon: const Icon(Icons.delete_outline),
                      label: Text(context.tr('diagnosticsClear')),
                    ),
                  ),
                ],
              ),
            ),

            SettingsSectionHeader(title: context.tr('diagnosticsEnvironment')),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_deviceInfo.isEmpty)
              ListTile(title: Text(context.tr('diagnosticsUnavailable')))
            else
              for (final key in _deviceInfo.keys)
                ListTile(
                  dense: true,
                  title: Text(key, style: theme.textTheme.bodySmall),
                  trailing: SelectableText(
                    _deviceInfo[key] ?? '',
                    style: theme.textTheme.bodySmall,
                  ),
                ),

            SettingsSectionHeader(title: context.tr('diagnosticsLog')),
            if (diagnostics.entries.isEmpty)
              ListTile(title: Text(context.tr('diagnosticsLogEmpty')))
            else
              for (final entry in diagnostics.entries) _LogLine(entry: entry),

            if (diagnostics.previousRun?.trim().isNotEmpty ?? false) ...<Widget>[
              SettingsSectionHeader(title: context.tr('diagnosticsPreviousRun')),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: SelectableText(
                  diagnostics.previousRun!,
                  style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (entry.level) {
      LogLevel.error => theme.colorScheme.error,
      LogLevel.warn => theme.colorScheme.tertiary,
      LogLevel.debug => theme.colorScheme.outline,
      LogLevel.info => theme.colorScheme.onSurface,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: SelectableText(
        entry.format(),
        style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', color: color),
      ),
    );
  }
}
