import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/browser/compat_script.dart';
import '../../core/dsh/dsh_endpoint.dart';
import '../../core/diagnostics/diagnostics.dart';
import '../../core/diagnostics/diagnostics_report.dart';
import '../../core/diagnostics/diagnostics_script.dart';
import '../../core/diagnostics/log_entry.dart';
import '../../core/diagnostics/redact.dart';
import '../../core/i18n/l10n.dart';
import '../../core/models/app_settings.dart';
import '../../core/models/dsh_device.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/notifications/web_notification_script.dart';
import '../../core/platform/app_platform.dart';
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
    this.isActive = true,
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

  /// Whether this session is the one on screen.

  /// Several sessions can be alive at once, and only one of them may ask the
  /// user for anything: a PIN dialog raised by a session behind the current
  /// one would land on top of a page the user is actually reading.
  final bool isActive;

  /// Called when the user types the password in the in-app prompt.
  final Future<void> Function(String password)? onPasswordEntered;

  final ValueChanged<String>? onTitleChanged;

  @override
  State<DshWebView> createState() => DshWebViewState();
}

class DshWebViewState extends State<DshWebView> {
  InAppWebViewController? _controller;
  bool _loading = true;
  String? _pageTitle;

  /// Why the page is unusable, if it is.
  _Failure? _failure;

  /// Raw technical detail behind [_failure] — an error description or a status
  /// line. Shown verbatim because it is the part that actually diagnoses.
  String? _detail;

  /// Result of the last page probe, kept so the failure screen can attach it to
  /// the report the user copies out.
  Map<String, Object?>? _probe;

  /// Guards against a page that never calls back at all. Without it the
  /// progress bar spins forever and the user has nothing to report.
  Timer? _loadTimeout;

  /// Runs once. The user is allowed to retry past a failed engine check, so
  /// this never blocks a deliberate second attempt.
  bool _engineChecked = false;

  /// Package name of the system WebView, so the failure screen can offer to
  /// open its settings page.
  String? _webViewPackage;

  /// A white screen is a page that loaded and painted nothing. It has no error
  /// code and no exception, so it is detected by asking the page itself.
  static const Duration _loadTimeoutAfter = Duration(seconds: 25);
  static const Duration _blankSettleDelay = Duration(milliseconds: 1200);

  /// One automatic retry per page session: enough to recover a rotated cookie,
  /// not enough to loop forever against a wrong password.
  bool _retriedWithStoredPassword = false;
  bool _promptVisible = false;

  /// The password the in-app prompt has already navigated with.
  ///
  /// Saving a password rebuilds this widget with a new [DshWebView.password],
  /// and that rebuild would otherwise start a navigation of its own — a second
  /// one, racing the navigation the prompt already began. Two navigations mean
  /// two login-form probes, and the second probe can still catch the login page
  /// and ask for the same PIN again. Recording what the prompt applied turns
  /// that rebuild into a no-op.
  String? _promptAppliedPassword;

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
  void initState() {
    super.initState();
    // From here on the PIN cannot appear in a log line, a probe result or a
    // report, no matter what the page echoes back at us.
    Diagnostics.instance.registerSecret(widget.password);
    unawaited(_logEnvironment());
  }

  /// Put the host facts at the top of the log.
  ///
  /// The WebView version is the single most useful line in a white-screen
  /// report: it decides whether the engine can run the bundle at all.
  Future<void> _logEnvironment() async {
    final info = await DiagnosticsReport.deviceInfo();
    if (info.isEmpty) return;
    Diagnostics.instance.info(
      'Device',
      '${info['manufacturer'] ?? ''} ${info['model'] ?? ''}'
      ' · Android ${info['androidRelease'] ?? '?'}'
      ' · MIUI ${info['miui'] ?? '-'}'
      ' · WebView ${info['webViewPackage'] ?? '?'} ${info['webViewVersion'] ?? '?'}',
    );
    final kernel = await AppPlatform.webViewKernel();
    if (kernel != null && kernel.isNotEmpty) {
      Diagnostics.instance.info('WebView', 'kernel: $kernel');
    }
  }

  @override
  void didUpdateWidget(DshWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    Diagnostics.instance.registerSecret(widget.password);
    if (oldWidget.device.id != widget.device.id) {
      _retriedWithStoredPassword = false;
      _promptAppliedPassword = null;
      _failure = null;
      _load(_entryUrl);
    } else if (oldWidget.password != widget.password) {
      if (widget.password != null && widget.password == _promptAppliedPassword) {
        // The prompt took this password and is already navigating with it.
        _promptAppliedPassword = null;
        return;
      }
      // The password changed somewhere else (the device config screen, or it
      // was cleared): apply it now.
      _retriedWithStoredPassword = false;
      _load(_entryUrl);
    } else if (!oldWidget.isActive && widget.isActive) {
      // This session sat behind another one and was not allowed to prompt;
      // now that it is on screen, give the stored password another go.
      _retriedWithStoredPassword = false;
      _load(_entryUrl);
    }
  }

  Future<void> _load(String url) async {
    final controller = _controller;
    if (controller == null) return;
    if (!_engineChecked) {
      _engineChecked = true;
      if (await _engineTooOld()) return;
      if (!mounted) return;
    }
    // Redacted at the source: the entry URL carries the access PIN.
    Diagnostics.instance.info('WebView', 'load ${Redact.url(url)}');
    setState(() {
      _loading = true;
      _failure = null;
      _detail = null;
      _probe = null;
    });
    _armTimeout();
    await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  /// Refuse to pretend an unparseable bundle might work.
  ///
  /// A WebView older than [CompatScript.minimumChromium] cannot even *parse*
  /// the DSH bundle, so the failure is certain and no shim can help. Loading
  /// anyway would produce the white screen this whole screen exists to
  /// replace. Returns true when the caller should stop.
  Future<bool> _engineTooOld() async {
    final info = await DiagnosticsReport.deviceInfo();
    final version = info['webViewVersion'];
    _webViewPackage = info['webViewPackage'];
    if (!CompatScript.isTooOld(version)) return false;

    final major = CompatScript.chromiumMajor(version);
    final detail = '${info['webViewPackage'] ?? 'WebView'} $version '
        '(Chromium $major < ${CompatScript.minimumChromium})';
    Diagnostics.instance.error('WebView', 'engine too old to parse the bundle: $detail');
    if (!mounted) return true;
    setState(() {
      _loading = false;
      _failure = _Failure.webViewTooOld;
      _detail = detail;
    });
    return true;
  }

  void _armTimeout() {
    _loadTimeout?.cancel();
    _loadTimeout = Timer(_loadTimeoutAfter, () {
      if (!mounted || !_loading) return;
      Diagnostics.instance.warn(
        'WebView',
        'no load callback after ${_loadTimeoutAfter.inSeconds}s',
      );
      setState(() {
        _loading = false;
        _failure = _Failure.timeout;
        _detail = null;
      });
    });
  }

  void _disarmTimeout() {
    _loadTimeout?.cancel();
    _loadTimeout = null;
  }

  /// Ask the page whether it actually rendered anything.
  Future<Map<String, Object?>?> _probePage(InAppWebViewController controller) async {
    try {
      final raw = await controller.evaluateJavascript(source: DiagnosticsScript.probeSource);
      if (raw is! String) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, Object?>();
      return null;
    } on Exception {
      // A page mid-navigation cannot answer; that is not a finding.
      return null;
    }
  }

  /// Public so the host tab can offer a manual reload.
  Future<void> reload() async {
    final controller = _controller;
    if (controller == null) return;
    _retriedWithStoredPassword = false;
    await _load(_entryUrl);
  }

  Future<void> goHome() => _load(_entryUrl);

  /// Throw away the cache and the session cookies, then reload.
  ///
  /// The escape hatch for a page that cached a broken response — the settings
  /// above already note that a stale cache shows up as a blank page, and until
  /// now the user had nothing to try when it did. Cookies are safe to drop:
  /// the entry URL re-mints them from the stored PIN on the next request.
  Future<void> hardReload() async {
    Diagnostics.instance.info('WebView', 'hard reload: clearing cache and cookies');
    try {
      await InAppWebViewController.clearAllCache();
      await CookieManager.instance().deleteAllCookies();
    } on Exception {
      // Best effort; reloading is still the right next step either way.
    }
    _retriedWithStoredPassword = false;
    await _load(_entryUrl);
  }

  @override
  void dispose() {
    _disarmTimeout();
    super.dispose();
  }

  Future<void> _handleLoadStop(InAppWebViewController controller, WebUri? url) async {
    if (!mounted) return;
    _disarmTimeout();
    Diagnostics.instance.info('WebView', 'loaded ${Redact.url(url?.toString() ?? '')}');

    var probe = await _probePage(controller);
    if (!mounted) return;

    // A framework can mount after the load event, so a blank document is only
    // called blank once it has had a moment to paint.
    if (probe != null && DiagnosticsScript.looksBlank(probe)) {
      await Future<void>.delayed(_blankSettleDelay);
      if (!mounted) return;
      probe = await _probePage(controller) ?? probe;
      if (!mounted) return;
    }

    final blank = probe != null && DiagnosticsScript.looksBlank(probe);
    if (probe != null) {
      Diagnostics.instance.log(
        blank ? LogLevel.warn : LogLevel.debug,
        'WebView',
        DiagnosticsScript.describeProbe(probe),
      );
    }

    setState(() {
      _loading = false;
      _probe = probe;
      if (blank) _failure = _Failure.blank;
    });

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

  void _handleConsoleMessage(InAppWebViewController controller, ConsoleMessage message) {
    final level = switch (message.messageLevel) {
      ConsoleMessageLevel.ERROR => LogLevel.error,
      ConsoleMessageLevel.WARNING => LogLevel.warn,
      _ => LogLevel.debug,
    };
    // ConsoleMessage carries only the text and the level; the source location
    // is not exposed by the platform interface.
    Diagnostics.instance.log(level, 'JS', message.message);
  }

  /// Diagnostics forwarded from the page's own error hooks.
  ///
  /// This is where an uncaught exception inside the DSH bundle surfaces — the
  /// single most likely explanation for a page that loads and paints nothing.
  void _handlePageDiagnostic(List<Object?> arguments) {
    if (arguments.isEmpty) return;
    final raw = arguments.first;
    if (raw is! Map) return;
    final level = switch (raw['level']?.toString()) {
      'error' => LogLevel.error,
      'warn' => LogLevel.warn,
      _ => LogLevel.info,
    };
    Diagnostics.instance.log(level, 'Page', (raw['message'] ?? '').toString());
  }

  Future<void> _handleLoginRequired() async {
    // A session the user is not looking at must not throw a dialog over the
    // one they are reading. It waits until it is brought to the front.
    if (!widget.isActive) return;
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
    // Recorded before the save, because saving is what rebuilds this widget
    // with the new password — and that rebuild must not navigate again.
    // Without a callback nothing rebuilds, so there is nothing to suppress.
    final onSaved = widget.onPasswordEntered;
    _promptAppliedPassword = onSaved == null ? null : entered;
    await onSaved?.call(entered);
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
            // Order matters. The shims go first: the DSH bundle needs them the
            // moment it starts evaluating, and a shim installed afterwards is
            // a shim installed too late.
            UserScript(
              source: CompatScript.source,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            // Then the error hooks, so they catch the page's own bootstrap.
            UserScript(
              source: DiagnosticsScript.source,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
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
            controller.addJavaScriptHandler(
              handlerName: DiagnosticsScript.handlerName,
              callback: (arguments) {
                _handlePageDiagnostic(arguments);
                return null;
              },
            );
          },
          onLoadStart: (controller, url) {
            if (mounted) {
              setState(() {
                _loading = true;
                _failure = null;
                _detail = null;
              });
            }
          },
          onLoadStop: _handleLoadStop,
          onConsoleMessage: _handleConsoleMessage,
          onReceivedError: (controller, request, error) {
            if (!mounted) return;
            final description = '${error.type}: ${error.description}';
            Diagnostics.instance.error(
              'WebView',
              'error on ${Redact.url(request.url.toString())} — $description',
            );
            // Sub-resource failures are noise: a missing favicon must not
            // replace a working page with an error screen.
            if (request.isForMainFrame != true) return;
            _disarmTimeout();
            setState(() {
              _loading = false;
              _failure = _Failure.network;
              _detail = description;
            });
          },
          // Not handled before, and it matters: a 401 from dsh-pocket still
          // fires onLoadStop, so the old code cleared the spinner and showed a
          // blank page with no explanation.
          onReceivedHttpError: (controller, request, response) {
            if (!mounted) return;
            final status = response.statusCode;
            final line = 'HTTP ${status ?? '?'} ${response.reasonPhrase ?? ''}'.trim();
            Diagnostics.instance.error(
              'WebView',
              'http error on ${Redact.url(request.url.toString())} — $line',
            );
            if (request.isForMainFrame != true) return;
            // 3xx and below are the WebView's own business.
            if (status != null && status < 400) return;
            _disarmTimeout();
            setState(() {
              _loading = false;
              _failure = _Failure.http;
              _detail = line;
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
        if (_failure != null)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: _FailureView(
                failure: _failure!,
                detail: _detail,
                device: widget.device,
                pageTitle: _pageTitle,
                probe: _probe,
                onRetry: () => _load(_entryUrl),
                onHardReload: hardReload,
                webViewPackage: _webViewPackage,
              ),
            ),
          ),
      ],
    );
  }
}

/// Why a page is not usable.
enum _Failure { timeout, network, http, blank, webViewTooOld }

/// The screen shown instead of a blank page.
///
/// A white screen is the worst failure mode this app has: the user cannot tell
/// a wrong address from a dead server from an obsolete WebView, and there is
/// nothing to report. This replaces it with what went wrong, what to try, and a
/// one-tap way to hand over the evidence.
class _FailureView extends StatelessWidget {
  const _FailureView({
    required this.failure,
    required this.detail,
    required this.device,
    required this.pageTitle,
    required this.probe,
    required this.onRetry,
    required this.onHardReload,
    this.webViewPackage,
  });

  final _Failure failure;
  final String? detail;
  final DshDevice device;
  final String? pageTitle;
  final Map<String, Object?>? probe;
  final VoidCallback onRetry;
  final VoidCallback onHardReload;

  /// Only set for [_Failure.webViewTooOld], to offer a shortcut to its settings.
  final String? webViewPackage;

  IconData get _icon => switch (failure) {
        _Failure.timeout => Icons.hourglass_empty,
        _Failure.network => Icons.cloud_off_outlined,
        _Failure.http => Icons.error_outline,
        _Failure.blank => Icons.visibility_off_outlined,
        _Failure.webViewTooOld => Icons.system_update_alt,
      };

  String _title(BuildContext context) => switch (failure) {
        _Failure.timeout => context.tr('webFailTimeout'),
        _Failure.network => context.tr('webFailNetwork'),
        _Failure.http => context.tr('webFailHttp'),
        _Failure.blank => context.tr('webFailBlank'),
        _Failure.webViewTooOld => context.tr('webViewTooOld'),
      };

  /// Concrete things to try, not "something went wrong".
  List<String> _hints(BuildContext context) => switch (failure) {
        _Failure.timeout => <String>[context.tr('webFailTimeoutHint')],
        _Failure.network => <String>[
            context.tr('webFailNetworkHint1'),
            context.tr('webFailNetworkHint2'),
          ],
        _Failure.http => <String>[
            context.tr('webFailHttpHint1'),
            context.tr('webFailHttpHint2'),
          ],
        _Failure.blank => <String>[
            context.tr('webFailBlankHint1'),
            context.tr('webFailBlankHint2'),
            context.tr('webFailBlankHint3'),
          ],
        _Failure.webViewTooOld => <String>[
            context.tr('webViewTooOldHint1'),
            context.tr('webViewTooOldHint2'),
            context.tr('webViewTooOldHint3'),
            context.tr('webViewTooOldHint4'),
          ],
      };

  Future<void> _copyReport(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final copied = context.tr('diagnosticsCopied');
    final failed = context.tr('diagnosticsCopyFailed');
    try {
      final report = await DiagnosticsReport.build(
        activeDevice: device.baseUrl,
        pageProbe: probe,
      );
      await Clipboard.setData(ClipboardData(text: report));
      messenger.showSnackBar(SnackBar(content: Text(copied)));
    } on Exception {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  Future<void> _shareReport(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.tr('diagnosticsShareFailed');
    try {
      final report = await DiagnosticsReport.build(
        activeDevice: device.baseUrl,
        pageProbe: probe,
      );
      final subject = await DiagnosticsReport.subject();
      final ok = await AppPlatform.shareText(text: report, subject: subject);
      if (!ok) messenger.showSnackBar(SnackBar(content: Text(failed)));
    } on Exception {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Icon(_icon, size: 44, color: theme.colorScheme.outline),
            const SizedBox(height: 14),
            Text(
              _title(context),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              device.address,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
            if (detail != null && detail!.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  detail!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ),
            const SizedBox(height: 18),
            for (final hint in _hints(context))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('·  ', style: theme.textTheme.bodySmall),
                    Expanded(
                      child: Text(hint, style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            if (failure == _Failure.webViewTooOld && webViewPackage != null) ...<Widget>[
              FilledButton.icon(
                onPressed: () => AppPlatform.openAppInfo(webViewPackage),
                icon: const Icon(Icons.settings_outlined),
                label: Text(context.tr('webViewOpenSettings')),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(context.tr('retry')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onHardReload,
              icon: const Icon(Icons.cleaning_services_outlined),
              label: Text(context.tr('webFailHardReload')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _copyReport(context),
              icon: const Icon(Icons.copy_all_outlined),
              label: Text(context.tr('diagnosticsCopy')),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _shareReport(context),
              icon: const Icon(Icons.ios_share),
              label: Text(context.tr('diagnosticsShare')),
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
