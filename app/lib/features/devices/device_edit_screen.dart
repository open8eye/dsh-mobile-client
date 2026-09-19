import 'package:flutter/material.dart';

import '../../core/dsh/dsh_endpoint.dart';
import '../../core/i18n/l10n.dart';
import '../../core/models/dsh_device.dart';

/// Result of the add/edit form.
class DeviceFormResult {
  const DeviceFormResult({
    required this.endpoint,
    required this.name,
    required this.password,
    required this.passwordChanged,
  });

  final DshEndpoint endpoint;
  final String name;

  /// `null` means "no password".
  final String? password;

  /// Whether the user actually edited the password field.
  final bool passwordChanged;
}

/// Add or edit one device.
class DeviceEditScreen extends StatefulWidget {
  const DeviceEditScreen({
    this.device,
    this.initialPassword,
    this.initialAddress,
    super.key,
  });

  /// `null` when adding a new device.
  final DshDevice? device;

  /// Pre-filled address when adding without a scan.
  final String? initialAddress;

  /// Existing password, shown only as "already saved" — never rendered back.
  final String? initialPassword;

  @override
  State<DeviceEditScreen> createState() => _DeviceEditScreenState();
}

class _DeviceEditScreenState extends State<DeviceEditScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _address = TextEditingController(
    text: widget.device?.baseUrl ?? widget.initialAddress ?? '',
  );
  late final TextEditingController _name =
      TextEditingController(text: widget.device?.name ?? '');
  final TextEditingController _password = TextEditingController();

  bool _passwordChanged = false;
  bool _obscure = true;
  String? _addressError;

  @override
  void dispose() {
    _address.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _hasStoredPassword => (widget.initialPassword ?? '').isNotEmpty;

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
    Navigator.of(context).pop(
      DeviceFormResult(
        endpoint: endpoint,
        name: _name.text.trim(),
        password: _password.text.trim().isEmpty ? null : _password.text.trim(),
        passwordChanged: _passwordChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              controller: _name,
              decoration: InputDecoration(
                labelText: context.tr('nicknameLabel'),
                hintText: context.tr('nicknameHint'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: context.tr('passwordLabel'),
                hintText: _hasStoredPassword ? context.tr('passwordSaved') : context.tr('passwordHint'),
                border: const OutlineInputBorder(),
                helperText: context.tr('passwordHelp'),
                helperMaxLines: 3,
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onChanged: (_) => _passwordChanged = true,
            ),
            if (_hasStoredPassword && !_passwordChanged)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.lock_outline, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        context.tr('passwordSaved'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _passwordChanged = true;
                          _password.clear();
                        });
                      },
                      child: Text(context.tr('delete')),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
