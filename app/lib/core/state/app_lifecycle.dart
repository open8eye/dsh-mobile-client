import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Tracks whether the app is in the foreground.
///
/// The notification bridge needs this to honour "only notify in the
/// background": a page notification raised while the user is looking at the
/// conversation should stay in the page.
class AppLifecycleObserver extends WidgetsBindingObserver {
  AppLifecycleObserver({AppLifecycleState initial = AppLifecycleState.resumed})
      : _state = ValueNotifier<AppLifecycleState>(initial);

  final ValueNotifier<AppLifecycleState> _state;

  ValueListenable<AppLifecycleState> get listenable => _state;

  bool get isForeground =>
      _state.value == AppLifecycleState.resumed ||
      _state.value == AppLifecycleState.inactive;

  void attach() => WidgetsBinding.instance.addObserver(this);

  void detach() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _state.value = state;
  }
}
