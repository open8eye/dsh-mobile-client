import 'package:flutter/material.dart';

import '../../core/dsh/dsh_endpoint.dart';
import '../../core/i18n/l10n.dart';
import '../../core/models/dsh_device.dart';

/// Result of the add/edit form.
class DeviceFormResult {
  const DeviceFormResult({
    required this.endpoint,
    required this.name,
    this.altBaseUrl = '',
    this.clearPassword = false,
  });

  final DshEndpoint endpoint;
  final String name;

  /// The server's other address, or an empty string for none. Always present,
  /// so an emptied field means "clear it" rather than "no opinion".
  final String altBaseUrl;

  /// The user asked to forget the access password stored for this device.
  final bool clearPassword;
}

/// Add or edit one device.
///
/// Deliberately has **no password field**. The access password is asked for by
/// a native prompt at the moment the server actually asks for it, which is also
/// the only moment a wrong PIN can be told from a right one. A field here made
/// the user type the same PIN twice — once into this form, and again when the
/// session opened — and the second prompt was the honest one anyway.
class DeviceEditScreen extends StatefulWidget {
  const DeviceEditScreen({
    this.device,
    this.initialAddress,
    super.key,
  });

  /// `null` when adding a new device.
  final DshDevice? device;

  /// Pre-filled address when adding without a scan.
  final String? initialAddress;

  @override
  State<DeviceEditScreen> createState() => _DeviceEditScreenState();
}

class _DeviceEditScreenState extends State<DeviceEditScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _address = TextEditingController(
    text: widget.device?.baseUrl ?? widget.initialAddress ?? '',
  );
  late final TextEditingController _alt = TextEditingController(
    text: (widget.device?.altBaseUrls.isNotEmpty ?? false)
        ? widget.device!.altBaseUrls.first
        : '',
  );
  late final TextEditingController _name =
      TextEditingController(text: widget.device?.name ?? '');

  /// Set once the user asks to forget the stored password. Only sent back on
  /// save, so backing out of the screen changes nothing.
  bool _clearPassword = false;
  String? _addressError;
  String? _altError;

  @override
  void dispose() {
    _address.dispose();
    _alt.dispose();
    _name.dispose();
    super.dispose();
  }

  /// A device being added has no password yet; `DshDevice.hasPassword` is the
  /// record of whether one is stored, so this screen never needs the secret.
  bool get _hasStoredPassword => widget.device?.hasPassword ?? false;

  void _submit() {
    final address = _address.text.trim();
    if (address.isEmpty) {
      setState(() => _addressError = context.tr('addressRequired'));
      return;
    }
    final endpoint = DshEndpoint.tryParse(address);
    if (endpoint == null) {
      setState(() => _addressError = context.tr('addressInvalid'));
      return;
    }

    var alt = _alt.text.trim();
    if (alt.isNotEmpty) {
      final parsedAlt = DshEndpoint.tryParse(alt);
      if (parsedAlt == null) {
        setState(() => _altError = context.tr('altAddressInvalid'));
        return;
      }
      if (parsedAlt.baseUrl == endpoint.baseUrl) {
        setState(() => _altError = context.tr('altAddressSame'));
        return;
      }
      // Stored normalised, so the probe and the dedupe both compare like
      // with like.
      alt = parsedAlt.baseUrl;
    }

    Navigator.of(context).pop(
      DeviceFormResult(
        endpoint: endpoint,
        name: _name.text.trim(),
        altBaseUrl: alt,
        clearPassword: _clearPassword,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.device != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(isEditing ? 'editDeviceTitle' : 'addDeviceTitle')),
        actions: <Widget>[
          TextButton(onPressed: _submit, child: Text(context.tr('save'))),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            TextFormField(
              controller: _address,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: context.tr('addressLabel'),
                hintText: context.tr('addressHint'),
                border: const OutlineInputBorder(),
                errorText: _addressError,
                helperText: context.tr('addressHint'),
              ),
              onChanged: (_) {
                if (_addressError != null) setState(() => _addressError = null);
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _alt,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: context.tr('altAddressLabel'),
                hintText: context.tr('altAddressHint'),
                border: const OutlineInputBorder(),
                errorText: _altError,
                helperText: context.tr('altAddressHelp'),
                helperMaxLines: 3,
              ),
              onChanged: (_) {
                if (_altError != null) setState(() => _altError = null);
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              decoration: InputDecoration(
                labelText: context.tr('nicknameLabel'),
                hintText: context.tr('nicknameHint'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            _buildPasswordRow(theme),
          ],
        ),
      ),
    );
  }

  /// What is stored, not what it is.
  ///
  /// The password itself is never rendered back and is not even passed into
  /// this screen — a settings page is exactly where a secret ends up in a
  /// screenshot.
  Widget _buildPasswordRow(ThemeData theme) {
    if (!_hasStoredPassword) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.lock_open_outlined, size: 18, color: theme.colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr('passwordNotSet'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            _clearPassword ? Icons.lock_open_outlined : Icons.lock_outline,
            size: 18,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr(_clearPassword ? 'passwordWillClear' : 'passwordSaved'),
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _clearPassword = !_clearPassword),
            child: Text(context.tr(_clearPassword ? 'passwordUndoClear' : 'passwordClear')),
          ),
        ],
      ),
    );
  }
}
