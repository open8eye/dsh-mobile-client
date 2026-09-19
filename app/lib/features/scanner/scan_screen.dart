import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/dsh/dsh_endpoint.dart';
import '../../core/i18n/l10n.dart';
import '../../core/platform/app_platform.dart';

/// Camera view that turns a dsh-pocket QR code into a device.
///
/// The QR code printed by dsh-pocket encodes a bare URL
/// (`http://192.168.1.5:3081`) — it deliberately does **not** embed the PIN.
/// So a scan usually yields an address without a password, and the user types
/// the 8-character PIN once on the confirmation screen.
///
/// The camera permission is requested by [MobileScanner] itself, which reports
/// the outcome through [MobileScanner.errorBuilder]; asking separately would
/// only duplicate that and pull in another dependency.
class ScanScreen extends StatefulWidget {
  const ScanScreen({required this.onScanned, required this.onManualEntry, super.key});

  /// Called with a parsed endpoint; the host decides what to do with it.
  final Future<void> Function(DshEndpoint endpoint) onScanned;

  /// The user would rather type an address than scan one.
  final VoidCallback onManualEntry;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
  );

  /// Guards against firing [ScanScreen.onScanned] twice for one code.
  bool _handled = false;
  String? _message;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .firstWhere((value) => value != null && value.trim().isNotEmpty, orElse: () => null);
    if (raw == null) return;

    final endpoint = DshEndpoint.tryParse(raw);
    if (endpoint == null) {
      if (!mounted) return;
      setState(() => _message = context.tr('scanInvalid'));
      return;
    }
    _handled = true;
    await widget.onScanned(endpoint);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) =>
              error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? const _PermissionView()
                  : _CameraErrorView(errorCode: error.errorCode),
        ),
        // Dim everything outside the scan window so the target is obvious.
        IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 0.9,
                colors: <Color>[
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.55),
                ],
                stops: const <double>[0.45, 1.0],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: <Widget>[
              const Spacer(),
              Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(context.tr('scanTitle'), style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      _message ?? context.tr('scanHint'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _message == null ? theme.colorScheme.outline : theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        TextButton.icon(
                          onPressed: () => _controller.toggleTorch(),
                          icon: const Icon(Icons.flashlight_on_outlined),
                          label: Text(context.tr('scanTorch')),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: widget.onManualEntry,
                          icon: const Icon(Icons.keyboard_alt_outlined),
                          label: Text(context.tr('scanManualEntry')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shown when the camera permission is denied.
class _PermissionView extends StatelessWidget {
  const _PermissionView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _CameraMessage(
      icon: Icons.no_photography_outlined,
      title: context.tr('scanPermissionTitle'),
      body: context.tr('scanPermissionBody'),
      actionLabel: context.tr('grantPermission'),
      onAction: () => AppPlatform.openAppSettings(),
      color: theme.colorScheme.outline,
    );
  }
}

/// Shown for any other camera failure, with the raw code so a bug report is
/// actionable.
class _CameraErrorView extends StatelessWidget {
  const _CameraErrorView({required this.errorCode});

  final MobileScannerErrorCode errorCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _CameraMessage(
      icon: Icons.videocam_off_outlined,
      title: context.tr('scanPermissionTitle'),
      body: errorCode.name,
      actionLabel: context.tr('grantPermission'),
      onAction: () => AppPlatform.openAppSettings(),
      color: theme.colorScheme.error,
    );
  }
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 48, color: color),
              const SizedBox(height: 16),
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}
