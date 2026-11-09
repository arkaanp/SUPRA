import 'package:flutter/material.dart';

import '../services/supra_api_service.dart';

/// Recovery links use Supabase's auth callback; email codes also work on Linux
/// without an OS deep-link handler (requires {{ .Token }} in the email template).
class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({
    super.key,
    this.verified = false,
    this.initialEmail = '',
  });
  final bool verified;
  final String initialEmail;
  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _sent = false, _verified = false, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _verified = widget.verified;
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = SupraService.instance;
      if (!_sent && !_verified) {
        await service.requestPasswordRecovery(_email.text);
        if (mounted) setState(() => _sent = true);
      } else if (!_verified) {
        await service.verifyRecoveryCode(_email.text, _code.text);
        if (mounted) setState(() => _verified = true);
      } else {
        if (_password.text != _confirmation.text) {
          throw StateError('Passwords do not match.');
        }
        await service.completePasswordRecovery(_password.text);
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Password updated.')));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _verified
              ? 'Could not update password. Use matching passwords with at least 8 characters, or request a fresh recovery link.'
              : _sent
              ? 'Code is invalid or expired. Request a fresh code and try again.'
              : 'Could not send recovery email. Check the address and try again later.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reset password')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_verified)
              TextField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
            if (_sent && !_verified) ...[
              const SizedBox(height: 12),
              const Text(
                'If this account exists, a recovery email has been sent. Open its recovery link or enter the recovery code below.',
              ),
              TextField(
                controller: _code,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Recovery code'),
              ),
              TextButton(
                onPressed: _busy ? null : () => setState(() => _sent = false),
                child: const Text('Send another email'),
              ),
            ],
            if (_verified) ...[
              TextField(
                controller: _password,
                obscureText: true,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'New password (at least 8 characters)',
                ),
              ),
              TextField(
                controller: _confirmation,
                obscureText: true,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                ),
              ),
            ],
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _busy ? null : _submit,
              child: Text(
                _busy
                    ? 'Please wait…'
                    : _verified
                    ? 'Update password'
                    : _sent
                    ? 'Verify code'
                    : 'Send recovery email',
              ),
            ),
            if (_verified)
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        await SupraService.instance.logout();
                        if (context.mounted) {
                          Navigator.of(context).popUntil((r) => r.isFirst);
                        }
                      },
                child: const Text('Cancel and sign out'),
              ),
          ],
        ),
      ),
    ),
  );
}
