import 'package:flutter/material.dart';

import 'sign_in_session.dart';
import '../notifications/notice_gateway.dart';
import '../settings/appearance.dart';
import '../setup/app_setup_page.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({
    super.key,
    required this.session,
    required this.noticeGateway,
    this.awaitingConfirmation = false,
  });

  final SignInSession session;
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
    if (_codeRequested) {
      final outcome = await widget.session.verifyCode(
        email: _emailController.text.trim(),
        code: _codeController.text.trim(),
      );
      if (!mounted) return;
      switch (outcome) {
        case SignInCodeVerified():
          break;
        case SignInCodeInvalid():
          setState(() {
            _error = 'That code did not work. Check it and try again.';
          });
      }
    } else {
      final outcome = await widget.session.requestCode(
        _emailController.text.trim(),
      );
      if (!mounted) return;
      switch (outcome) {
        case SignInCodeSent():
          setState(() => _codeRequested = true);
        case SignInEmailInvalid():
          setState(() {
            _error = 'That email address is not valid. Enter it again.';
          });
        case SignInCodeNotSent():
          setState(() {
            _error = 'We could not send a code right now. Try again later.';
          });
      }
    }
    if (mounted) setState(() => _busy = false);
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
