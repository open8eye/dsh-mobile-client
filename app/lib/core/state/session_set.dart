import 'dart:collection';

/// The set of live sessions, ordered least recently used first.
///
/// A "session" is a device that is currently connected in this process — its
/// WebView is alive and switching to it costs nothing. The set is deliberately
/// session-only: a WebView does not survive the process, so persisting it would
/// promise something the next launch cannot keep.
///
/// Kept apart from the widget that owns the WebViews so the ordering rules —
/// which are the part that can quietly lose a user's session — are testable on
/// their own.
class SessionSet {
  SessionSet({this.maxSessions = 4}) : assert(maxSessions >= 1);

  /// How many sessions may be alive at once.
  ///
  /// Every live WebView keeps a Chromium renderer resident, tens of megabytes
  /// each, so the oldest one is dropped rather than letting the process be
  /// killed for the whole app.
  final int maxSessions;

  final List<String> _ids = <String>[];
  String? _currentId;

  /// Least recently used first. The current session is normally last.
  List<String> get ids => UnmodifiableListView<String>(_ids);

  String? get currentId => _currentId;

  int get length => _ids.length;

  bool get isEmpty => _ids.isEmpty;

  bool contains(String id) => _ids.contains(id);

  /// Bring [id] up, opening it if it is not already live.
  ///
  /// Returns the ids that had to be dropped to stay under [maxSessions], so the
  /// caller can dispose their WebViews. The session being opened is never one
  /// of them.
  List<String> open(String id) {
    _ids
      ..remove(id)
      ..add(id);
    _currentId = id;

    final dropped = <String>[];
    while (_ids.length > maxSessions && _ids.first != id) {
      dropped.add(_ids.removeAt(0));
    }
    return dropped;
  }

  /// Make an already-open session current. False when it is not open — the
  /// caller must not invent a session that has no WebView behind it.
  bool activate(String id) {
    if (!_ids.contains(id)) return false;
    _ids
      ..remove(id)
      ..add(id);
    _currentId = id;
    return true;
  }

  /// Drop [id]. False when it was not open.
  bool close(String id) {
    if (!_ids.remove(id)) return false;
    if (_currentId == id) {
      _currentId = _ids.isEmpty ? null : _ids.last;
    }
    return true;
  }

  /// Drop everything whose id is not in [keep], and return what was dropped.
  ///
  /// Used when devices are deleted: a session whose device is gone has nothing
  /// left to show.
  List<String> retain(Set<String> keep) {
    final dropped = _ids.where((id) => !keep.contains(id)).toList();
    if (dropped.isEmpty) return dropped;
    _ids.removeWhere((id) => !keep.contains(id));
    if (_currentId != null && !_ids.contains(_currentId)) {
      _currentId = _ids.isEmpty ? null : _ids.last;
    }
    return dropped;
  }
}
