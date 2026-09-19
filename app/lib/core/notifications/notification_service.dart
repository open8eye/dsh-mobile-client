import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Turns forwarded page notifications into real system notifications.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const String _channelId = 'dsh_messages';
  static const String _channelName = 'DSH 消息';
  static const String _channelDescription = '来自 DeepSeek Harness 网页的通知';

  bool _initialised = false;

  Future<void> init() async {
    if (_initialised) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: darwin, macOS: darwin),
    );
    _initialised = true;
  }

  /// Ask the OS for permission. Returns whether notifications may be posted.
  Future<bool> requestPermission() async {
    await init();
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? true;
    }
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? true;
    }
    return true;
  }

  Future<bool> hasPermission() async {
    await init();
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? true;
    }
    return true;
  }

  /// Post one notification.
  ///
  /// [tag] makes repeated updates for the same conversation replace each other
  /// instead of stacking, which is what a chat UI expects.
  Future<void> show({
    required String title,
    required String body,
    String? tag,
  }) async {
    await init();
    final cleanTitle = title.trim();
    final cleanBody = body.trim();
    if (cleanTitle.isEmpty && cleanBody.isEmpty) return;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: cleanBody.isEmpty
            ? null
            : BigTextStyleInformation(cleanBody, contentTitle: cleanTitle.isEmpty ? null : cleanTitle),
      ),
      iOS: const DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
    );
    final id = (tag == null || tag.isEmpty) ? DateTime.now().millisecondsSinceEpoch.remainder(1 << 31) : tag.hashCode.remainder(1 << 31);
    try {
      await _plugin.show(
        id: id,
        title: cleanTitle.isEmpty ? null : cleanTitle,
        body: cleanBody.isEmpty ? null : cleanBody,
        notificationDetails: details,
        payload: tag,
      );
    } on Exception catch (error) {
      // A failed notification must never break the WebView call that raised it.
      debugPrint('NotificationService: could not show notification: $error');
    }
  }
}
