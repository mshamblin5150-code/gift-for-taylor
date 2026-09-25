import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'sign_in_failure_log.dart';

class SignInFailuresPage extends StatefulWidget {
  const SignInFailuresPage({super.key, required this.log});

  final SignInFailureLog log;

  @override
  State<SignInFailuresPage> createState() => _SignInFailuresPageState();
}

class _SignInFailuresPageState extends State<SignInFailuresPage> {
  late final Future<List<SignInFailureRecord>> _failures = widget.log.read();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sign-in failures')),
    body: FutureBuilder<List<SignInFailureRecord>>(
      future: _failures,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load sign-in failures.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(child: Text('No sign-in failures.'));
        }
        return ListView(
          children: [
            for (final failure in snapshot.data!)
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
        );
      },
    ),
  );
}
