import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/dsh/dsh_endpoint.dart';
import '../../core/i18n/l10n.dart';
import '../../core/models/app_settings.dart';
import '../../core/models/dsh_device.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/notifications/web_notification_script.dart';
import '../../core/state/app_lifecycle.dart';

/// Full-screen WebView onto one DSH server.
///
/// The whole point of this app is in this widget: the DSH web session is a
/// cookie bound to the server process, and `dsh-pocket` rotates that binding
/// whenever `dsh web` restarts. A plain browser then shows the PIN form again.
/// Here the stored password is re-applied automatically by re-entering through
/// `/?token=<password>`, which the server accepts and answers with a fresh
/// cookie — so the user never types it a second time.
class DshWebView extends StatefulWidget {
  const DshWebView({
    required this.device,
    required this.password,
    required this.settings,
    required this.lifecycle,
    required this.notificationService,
    this.onPasswordEntered,
    this.onTitleChanged,
    super.key,
  });

  final DshDevice device;

  /// Access password read from the keystore; `null` when none is stored.
  final String? password;

  final AppSettings settings;
  final AppLifecycleObserver lifecycle;
  final NotificationService notificationService;

  /// Called when the user types the password in the in-app prompt.
  final Future<void> Function(String password)? onPasswordEntered;

  final ValueChanged<String>? onTitleChanged;

  @override
  State<DshWebView> createState() => DshWebViewState();
}

class DshWebViewState extends State<DshWebView> {
  InAppWebViewController? _controller;
  bool _loading = true;
  String? _error;
  String? _pageTitle;

  /// One automatic retry per page session: enough to recover a rotated cookie,
  /// not enough to loop forever against a wrong password.
  bool _retriedWithStoredPassword = false;
  bool _promptVisible = false;

  DshEndpoint get _endpoint =>
      DshEndpoint.tryParse(widget.device.baseUrl) ??
      DshEndpoint(baseUrl: widget.device.baseUrl, kind: widget.device.kind);

  /// Entry URL for this session.
  ///
  /// Preferring `?token=` means the very first request already carries the
  /// password, so the user normally never sees the login page at all.
  String get _entryUrl {
    final password = widget.password;
    if (password != null && password.isNotEmpty && widget.settings.autoReconnect) {
      return _endpoint.authenticatedUrl(password);
    }
    return _endpoint.plainUrl;
  }

  @override
  void didUpdateWidget(DshWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.id != widget.device.id) {
      _retriedWithStoredPassword = false;
      _error = null;
      _load(_entryUrl);
    } else if (oldWidget.password != widget.password) {
      // A password was just saved from the prompt: retry immediately.
      _retriedWithStoredPassword = false;
      _load(_entryUrl);
    }
  }

  Future<void> _load(String url) async {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  /// Public so the host tab can offer a manual reload.
  Future<void> reload() async {
    final controller = _controller;
    if (controller == null) return;
    _retriedWithStoredPassword = false;
    await _load(_entryUrl);
  }

  Future<void> goHome() => _load(_entryUrl);

  Future<void> _handleLoadStop(InAppWebViewController controller, WebUri? url) async {
    if (!mounted) return;
    setState(() => _loading = false);
    try {
      final result = await controller.evaluateJavascript(
        source: WebNotificationScript.probeLoginForm,
      );
      if (result == 'login') {
        await _handleLoginRequired();
      }
    } on Exception {
      // A page that vanished mid-probe is not an error worth surfacing.
    }
  }

  Future<void> _handleLoginRequired() async {
    final stored = widget.password;
    if (stored != null && stored.isNotEmpty && !_retriedWithStoredPassword) {
      _retriedWithStoredPassword = true;
      await _load(_endpoint.authenticatedUrl(stored));
      return;
    }
    if (_promptVisible || !mounted) return;
    _promptVisible = true;
    final entered = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PasswordPromptDialog(device: widget.device),
    );
    _promptVisible = false;
    if (entered == null || entered.isEmpty) return;
    await widget.onPasswordEntered?.call(entered);
    _retriedWithStoredPassword = true;
    await _load(_endpoint.authenticatedUrl(entered));
  }

  /// Hand a non-DSH link to the operating system.
  Future<void> _openExternally(WebUri uri) async {
    try {
      await launchUrl(Uri.parse(uri.toString()), mode: LaunchMode.externalApplication);
    } on Exception {
      // No handler for the scheme; dropping it is the only option left.
    }
  }

  Future<void> _handleNotification(List<Object?> arguments) async {
    if (!widget.settings.notificationsEnabled) return;
    if (widget.settings.notifyOnlyInBackground && widget.lifecycle.isForeground) return;
    if (arguments.isEmpty) return;
    final raw = arguments.first;
    if (raw is! Map) return;
    final title = (raw['title'] ?? '').toString();
    final body = (raw['body'] ?? '').toString();
    final tag = (raw['tag'] ?? '').toString();
    await widget.notificationService.show(
      title: title.isEmpty ? widget.device.name : title,
      body: body,
      tag: tag.isEmpty ? widget.device.id : '${widget.device.id}:$tag',
    );
  }

  @override
  Widget build(BuildContext context) {
    final deviceHost = Uri.parse(widget.device.baseUrl).host;
    return Stack(
      children: <Widget>[
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(_entryUrl)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            databaseEnabled: true,
            thirdPartyCookiesEnabled: true,
            useShouldOverrideUrlLoading: true,
            useOnDownloadStart: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            supportZoom: false,
            transparentBackground: false,
            // The DSH shell reads window.__DSH_BOOT__ and keeps its own state;
            // a stale cache across restarts shows a blank page.
            clearCache: false,
            cacheEnabled: true,
            userAgent: '',
          ),
          initialUserScripts: UnmodifiableListView<UserScript>(<UserScript>[
            UserScript(
              source: WebNotificationScript.source,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
          ]),
          onWebViewCreated: (controller) {
            _controller = controller;
            controller.addJavaScriptHandler(
              handlerName: WebNotificationScript.handlerName,
              callback: (arguments) {
                _handleNotification(arguments);
                return null;
              },
            );
          },
          onLoadStart: (controller, url) {
            if (mounted) setState(() => _loading = true);
          },
          onLoadStop: _handleLoadStop,
          onReceivedError: (controller, request, error) {
            if (!mounted) return;
            if (request.isForMainFrame != true) return;
            setState(() {
              _loading = false;
              _error = error.description;
            });
          },
          onTitleChanged: (controller, title) {
            _pageTitle = title;
            widget.onTitleChanged?.call(title ?? '');
          },
          onPermissionRequest: (controller, request) async {
            // The DSH page may ask for the microphone or camera for attachments.
            return PermissionResponse(
              resources: request.resources,
              action: PermissionResponseAction.GRANT,
            );
          },
          onReceivedServerTrustAuthRequest: (controller, challenge) async {
            // Home servers and NAS boxes routinely use a self-signed
            // certificate; refusing here would make them unreachable.
            return ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.PROCEED);
          },
          shouldOverrideUrlLoading: (controller, action) async {
            final uri = action.request.url;
            if (uri == null) return NavigationActionPolicy.ALLOW;
            final scheme = uri.scheme;
            if (scheme == 'http' || scheme == 'https') {
              if (uri.host == deviceHost) return NavigationActionPolicy.ALLOW;
              // Anything off-device belongs in the real browser. Cancelling
              // without handing it off would make those links dead.
              unawaited(_openExternally(uri));
              return NavigationActionPolicy.CANCEL;
            }
            if (scheme == 'mailto' || scheme == 'tel') {
              unawaited(_openExternally(uri));
            }
            return NavigationActionPolicy.CANCEL;
          },
        ),
        if (_loading)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_error != null)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: _ErrorView(
                message: _error!,
                device: widget.device,
                pageTitle: _pageTitle,
                onRetry: () => _load(_entryUrl),
              ),
            ),
          ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.device,
    required this.pageTitle,
    required this.onRetry,
  });

  final String message;
  final DshDevice device;
  final String? pageTitle;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.cloud_off_outlined, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(context.tr('failed'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '${device.address}\n$message',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(context.tr('retry')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Native replacement for the dsh-pocket web login form.
class _PasswordPromptDialog extends StatefulWidget {
  const _PasswordPromptDialog({required this.device});

  final DshDevice device;

  @override
  State<_PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<_PasswordPromptDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('loginRequiredTitle')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(context.tr('loginRequiredBody'), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.visiblePassword,
            decoration: InputDecoration(
              labelText: context.tr('passwordLabel'),
              hintText: widget.device.address,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(context.tr('loginSubmit')),
        ),
      ],
    );
  }
}
