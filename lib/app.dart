import 'package:flutter/material.dart';
import 'package:schedule_rules/schedule_rules.dart';

import 'auth/auth_gateway.dart';
import 'auth/sign_in_page.dart';
import 'schedule/month_grid_page.dart';
import 'schedule/section_gateway.dart';

class ScheduleApp extends StatelessWidget {
  const ScheduleApp({
    super.key,
    required this.authGateway,
    required this.sectionGateway,
  });

  final AuthGateway authGateway;
  final SectionGateway sectionGateway;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ER Schedule',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff24535c)),
        useMaterial3: true,
      ),
      home: _AuthGate(authGateway: authGateway, sectionGateway: sectionGateway),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate({required this.authGateway, required this.sectionGateway});

  final AuthGateway authGateway;
  final SectionGateway sectionGateway;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: authGateway.signedInChanges,
      initialData: authGateway.isSignedIn,
      builder: (context, snapshot) {
        if (snapshot.data != true) {
          return SignInPage(authGateway: authGateway);
        }
        return _ScheduleAccess(
          authGateway: authGateway,
          sectionGateway: sectionGateway,
        );
      },
    );
  }
}

class _ScheduleAccess extends StatefulWidget {
  const _ScheduleAccess({
    required this.authGateway,
    required this.sectionGateway,
  });

  final AuthGateway authGateway;
  final SectionGateway sectionGateway;

  @override
  State<_ScheduleAccess> createState() => _ScheduleAccessState();
}

class _ScheduleAccessState extends State<_ScheduleAccess> {
  late final Future<List<ScheduleSection>> _sections = widget.sectionGateway
      .loadSections();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ScheduleSection>>(
      future: _sections,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final sections = snapshot.data ?? const <ScheduleSection>[];
        if (snapshot.hasError || sections.isEmpty) {
          return Scaffold(
            appBar: AppBar(
              actions: [
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: widget.authGateway.signOut,
                  icon: const Icon(Icons.logout),
                ),
              ],
            ),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This email is not on the ER Staff list. '
                  'Please ask the Manager for an Invite.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final now = DateTime.now();
        return MonthGridPage(
          month: DateTime(now.year, now.month),
          sections: sections,
          onSignOut: widget.authGateway.signOut,
        );
      },
    );
  }
}
