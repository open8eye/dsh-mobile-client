import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/i18n/l10n.dart';
import 'core/state/settings_controller.dart';
import 'features/home/home_shell.dart';

/// Root widget: theme, locale and the shell.
class DshMobileApp extends StatelessWidget {
  const DshMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final code = settings.resolveLocaleCode(
      WidgetsBinding.instance.platformDispatcher.locales,
    );

    return L10nScope(
      l10n: L10n(code),
      child: MaterialApp(
        title: 'DSH Mobile',
        debugShowCheckedModeBanner: false,
        themeMode: settings.settings.themeMode,
        locale: Locale(code),
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: const HomeShell(),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF4D6BFE),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        centerTitle: false,
      ),
    );
  }
}
