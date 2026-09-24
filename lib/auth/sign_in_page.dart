import 'package:flutter/material.dart';

import 'auth_gateway.dart';
import '../notifications/notice_gateway.dart';
import '../settings/appearance.dart';
import '../setup/app_setup_page.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({
    super.key,
    required this.authGateway,
    required this.noticeGateway,
    this.awaitingConfirmation = false,
  });

  final AuthGateway authGateway;
  final NoticeGateway noticeGateway;
  final bool awaitingConfirmation;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  bool _codeRequested = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_codeRequested) {
        await widget.authGateway.verifyCode(
          email: _emailController.text.trim(),
          code: _codeController.text.trim(),
        );
      } else {
        await widget.authGateway.requestCode(_emailController.text.trim());
        if (mounted) setState(() => _codeRequested = true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = _codeRequested
              ? 'That code did not work. Check it and try again.'
              : 'We could not send a code. Check the email and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(actions: const [AppearanceButton()]),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'ER Schedule',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _codeRequested
                            ? 'Enter the one-time code sent to your email.'
                            : 'Accept your Invite or sign in with your '
                                  'personal email.',
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _emailController,
                        enabled: !_codeRequested && !_busy,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (_codeRequested) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _codeController,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          decoration: const InputDecoration(
                            labelText: 'One-time code',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: Text(
                          _codeRequested ? 'Verify code' : 'Email me a code',
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => AppSetupPage(
                              noticeGateway: widget.noticeGateway,
                              awaitingConfirmation: widget.awaitingConfirmation,
                            ),
                          ),
                        ),
                        child: const Text('Add ER Schedule'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
