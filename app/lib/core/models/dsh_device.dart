import 'package:flutter/foundation.dart';

/// How a DSH entry point is reached from the phone.
///
/// The distinction matters for two reasons: the badge shown in the device
/// list, and the hint text shown when a password is missing. It never changes
/// which password is accepted — that decision belongs to the server.
enum DshAccessKind {
  /// RFC1918 / mDNS / single-label host: same Wi-Fi as the computer.
  lan,

  /// CGNAT 100.64.0.0/10: the Tailscale address of the computer.
  tailscale,

  /// A public hostname, typically a cloudflared quick tunnel.
  tunnel,

  /// Loopback or anything we cannot classify.
  custom,
}

/// One saved DSH server, as the user sees it in the device list.
///
/// The access password is deliberately **not** part of this model: it lives in
/// the platform keystore (see [SecretStore]) and is looked up by [id]. Only
/// [hasPassword] is persisted here, so the list can show a lock badge without
/// ever touching the secret.
@immutable
class DshDevice {
  const DshDevice({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.kind,
    this.hasPassword = false,
    this.lastConnectedAt,
    this.createdAt,
  });

  /// Stable identifier; also the keystore key for this device's password.
  final String id;

  /// User-editable nickname, e.g. "书房台式机".
  final String name;

  /// Normalised origin including any reverse-proxy sub-path, without a
  /// trailing slash and without a `token` query parameter.
  final String baseUrl;

  final DshAccessKind kind;

  /// Whether a password is currently stored for this device.
  final bool hasPassword;

  final DateTime? lastConnectedAt;
  final DateTime? createdAt;

  Uri get uri => Uri.parse(baseUrl);

  String get host => uri.host;

  int get port => uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);

  /// "192.168.1.5:3081" — what the user needs to recognise the entry.
  String get address => '$host:$port';

  /// Default nickname proposed when a device is first created.
  static String defaultNameFor(String host, DshAccessKind kind) {
    switch (kind) {
      case DshAccessKind.tailscale:
        return 'Tailscale · $host';
      case DshAccessKind.tunnel:
        return host;
      case DshAccessKind.lan:
      case DshAccessKind.custom:
        return host;
    }
  }

  DshDevice copyWith({
    String? name,
    String? baseUrl,
    DshAccessKind? kind,
    bool? hasPassword,
    DateTime? lastConnectedAt,
    DateTime? createdAt,
  }) {
    return DshDevice(
      id: id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      kind: kind ?? this.kind,
      hasPassword: hasPassword ?? this.hasPassword,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'kind': kind.name,
        'hasPassword': hasPassword,
        if (lastConnectedAt != null) 'lastConnectedAt': lastConnectedAt!.toIso8601String(),
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      };

  static DshDevice? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    final baseUrl = json['baseUrl'];
    if (id is! String || name is! String || baseUrl is! String) return null;
    return DshDevice(
      id: id,
      name: name,
      baseUrl: baseUrl,
      kind: DshAccessKind.values.firstWhere(
        (value) => value.name == json['kind'],
        orElse: () => DshAccessKind.custom,
      ),
      hasPassword: json['hasPassword'] == true,
      lastConnectedAt: _parseDate(json['lastConnectedAt']),
      createdAt: _parseDate(json['createdAt']),
    );
  }

  static DateTime? _parseDate(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  @override
  bool operator ==(Object other) => other is DshDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
