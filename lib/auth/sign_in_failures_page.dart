import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'sign_in_failure_log.dart';
import 'sign_in_failures_session.dart';

class SignInFailuresPage extends StatefulWidget {
  const SignInFailuresPage({super.key, required this.log});

  final SignInFailureLog log;

  @override
  State<SignInFailuresPage> createState() => _SignInFailuresPageState();
}

class _SignInFailuresPageState extends State<SignInFailuresPage> {
  late final SignInFailuresSession _session = SignInFailuresSession(widget.log)
    ..load();

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sign-in failures')),
    body: ListenableBuilder(
      listenable: _session,
      builder: (context, _) => switch (_session.state) {
        SignInFailuresLoading() => const Center(
          child: CircularProgressIndicator(),
        ),
        SignInFailuresFailed() => const Center(
          child: Text('Could not load sign-in failures.'),
        ),
        SignInFailuresLoaded(:final failures) when failures.isEmpty =>
          const Center(child: Text('No sign-in failures.')),
        SignInFailuresLoaded(:final failures) => ListView(
          children: [
            for (final failure in failures)
              ListTile(
                title: Text(failure.code ?? 'Provider failure'),
                subtitle: Text(
                  '${DateFormat.yMMMd().add_jm().format(failure.happenedAt.toLocal())}'
                  '${failure.statusCode == null ? '' : ' · HTTP ${failure.statusCode}'}'
                  '\n${failure.message}',
                ),
                isThreeLine: true,
              ),
          ],
        ),
      },
    ),
  );
}
