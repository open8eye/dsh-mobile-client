import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/l10n.dart';
import '../../core/pet/pet_platform.dart';
import '../../core/state/settings_controller.dart';
import '../settings/settings_widgets.dart';
import 'companion_preview.dart';

/// The companion preferences: switch, image, size, opacity.
///
/// Only built when [PetFeature.available] is true. Kept in the tree while the
/// feature is on hold so it stays compiled and analysed.
class CompanionSettingsSection extends StatefulWidget {
  const CompanionSettingsSection({super.key});

  @override
  State<CompanionSettingsSection> createState() => _CompanionSettingsSectionState();
}

class _CompanionSettingsSectionState extends State<CompanionSettingsSection>
    with WidgetsBindingObserver {
  /// Set when the user asked for the companion but still has to grant the
  /// overlay permission on the system screen. Android gives us no callback for
  /// that screen, so the request is completed when the app comes back.
  bool _pendingPetEnable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_pendingPetEnable) return;
    _pendingPetEnable = false;
    _enablePet(context.read<SettingsController>());
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _togglePet(bool value, SettingsController settings) async {
    if (!value) {
      await context.read<PetPlatform>().hide();
      await settings.setPetEnabled(false);
      if (!mounted) return;
      _snack(context.tr('petDisabled'));
      return;
    }
    await _enablePet(settings);
  }

  /// Turn the companion on, granting the overlay permission first if needed.
  Future<void> _enablePet(SettingsController settings) async {
    final pet = context.read<PetPlatform>();
    final supported = await pet.isSupported();
    if (!mounted) return;
    if (!supported) {
      _snack(context.tr('petUnsupported'));
      return;
    }

    var granted = await pet.hasOverlayPermission();
    if (!granted) {
      await pet.requestOverlayPermission();
      // The system screen has no result; finish the job on resume instead of
      // telling the user to flip the switch a second time.
      _pendingPetEnable = true;
      if (!mounted) return;
      _snack(context.tr('petPermissionDenied'));
      return;
    }

    final current = settings.settings;
    final shown = await pet.show(
      scale: current.petScale,
      opacity: current.petOpacity,
      imagePath: current.petImagePath,
    );
    if (!mounted) return;
    if (!shown) {
      _snack(context.tr('petPermissionDenied'));
      return;
    }
    await settings.setPetEnabled(true);
    if (!mounted) return;
    _snack(context.tr('petEnabled'));
  }

  /// Copy the picked image into the app data directory.
  ///
  /// image_picker returns a path inside the system cache, which Android is free
  /// to delete; a companion that disappears after a reboot would look like a bug.
  Future<String?> _persistCompanionImage(String sourcePath) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final dot = sourcePath.lastIndexOf('.');
      final extension = sourcePath.contains('.') ? sourcePath.substring(dot) : '.png';
      final target = File('${dir.path}/companion$extension');
      await File(sourcePath).copy(target.path);
      return target.path;
    } on Exception {
      return sourcePath;
    }
  }

  Future<void> _pickCompanionImage(SettingsController settings) async {
    final pet = context.read<PetPlatform>();
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final stored = await _persistCompanionImage(picked.path);
    await settings.setPetImagePath(stored);
    final current = settings.settings;
    if (current.petEnabled) {
      await pet.show(
        scale: current.petScale,
        opacity: current.petOpacity,
        imagePath: stored,
      );
    }
  }

  Future<void> _resize(SettingsController settings, {double? scale, double? opacity}) async {
    final pet = context.read<PetPlatform>();
    final current = settings.settings;
    if (!current.petEnabled) return;
    await pet.show(
      scale: scale ?? current.petScale,
      opacity: opacity ?? current.petOpacity,
      imagePath: current.petImagePath,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final current = settings.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SettingsSectionHeader(title: context.tr('settingsCompanion')),
        ListTile(
          leading: SizedBox(
            width: 56,
            height: 56,
            child: current.petImagePath == null
                ? const CompanionPreview(size: 56)
                : Image.file(File(current.petImagePath!), fit: BoxFit.contain),
          ),
          title: Text(context.tr('settingsPetEnabled')),
          subtitle: Text(context.tr('settingsPetEnabledHint')),
          trailing: Switch(
            value: current.petEnabled,
            onChanged: (value) => _togglePet(value, settings),
          ),
        ),
        ListTile(
          title: Text(context.tr('settingsPetPickImage')),
          trailing: const Icon(Icons.image_outlined),
          onTap: () => _pickCompanionImage(settings),
        ),
        if (current.petImagePath != null)
          ListTile(
            title: Text(context.tr('settingsPetResetImage')),
            trailing: const Icon(Icons.restart_alt),
            onTap: () => settings.setPetImagePath(null),
          ),
        ListTile(
          title: Text(context.tr('settingsPetScale')),
          subtitle: Slider(
            value: current.petScale,
            min: 0.5,
            max: 2.0,
            divisions: 6,
            label: current.petScale.toStringAsFixed(1),
            onChanged: settings.setPetScale,
            onChangeEnd: (value) => _resize(settings, scale: value),
          ),
        ),
        ListTile(
          title: Text(context.tr('settingsPetOpacity')),
          subtitle: Slider(
            value: current.petOpacity,
            min: 0.3,
            max: 1.0,
            divisions: 7,
            label: current.petOpacity.toStringAsFixed(1),
            onChanged: settings.setPetOpacity,
            onChangeEnd: (value) => _resize(settings, opacity: value),
          ),
        ),
      ],
    );
  }
}
