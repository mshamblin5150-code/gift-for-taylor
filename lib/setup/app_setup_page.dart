import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../help/help_page.dart';
import '../notifications/notice_gateway.dart';
import 'install_browser.dart' as browser;
import 'install_guidance.dart';

/// The shareable app address never contains an Invite token or other URL state.
Uri ordinaryAppUri(Uri current) => Uri(
  scheme: current.scheme,
  host: current.host,
  port: current.hasPort ? current.port : null,
  path: current.path,
);

class AppSetupPage extends StatefulWidget {
  const AppSetupPage({
    super.key,
    required this.noticeGateway,
    this.awaitingConfirmation = false,
    this.canAllowNotifications = false,
    this.helpRoles = const {HelpRole.staffMember},
  });

  final NoticeGateway noticeGateway;
  final bool awaitingConfirmation;
  final bool canAllowNotifications;
  final Set<HelpRole> helpRoles;

  @override
  State<AppSetupPage> createState() => _AppSetupPageState();
}

class _AppSetupPageState extends State<AppSetupPage> {
  Timer? _refresh;
  browser.InstallState _installState = browser.installState();
  late Future<PushState> _pushState = _readPushState();
  bool _busy = false;
  bool _installing = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = browser.installState();
      if (mounted && next != _installState) {
        setState(() => _installState = next);
      }
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _message = null;
    });
    final result = await browser.promptInstall();
    if (!mounted) return;
    setState(() {
      _installing = false;
      _installState = browser.installState();
      _message = switch (result) {
        browser.InstallPromptResult.accepted =>
          'Installation started. Open ER Schedule from its new icon.',
        browser.InstallPromptResult.dismissed => 'Installation was skipped. Use the phone steps below whenever you are ready.',
        browser.InstallPromptResult.unavailable =>
          'The install offer is unavailable. Use the phone steps below.',
      };
    });
  }

  Future<PushState> _readPushState() async {
    try {
      return await widget.noticeGateway.pushState();
    } catch (_) {
      return PushState.unsupported;
    }
  }

  Future<void> _allowNotifications() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.noticeGateway.allowPush();
      if (mounted) {
        setState(() {
          _message = 'Notifications allowed in this place.';
          _pushState = _readPushState();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Notifications were not allowed. Check the browser or app settings and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(
      ClipboardData(text: ordinaryAppUri(Uri.base).toString()),
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('App link copied.')));
    }
  }

  Widget _notificationStep(PushState state) {
    if (!widget.canAllowNotifications) {
      if (widget.helpRoles.contains(HelpRole.maintainer)) {
        return const Text(
          'Notification setup is available after signing in as a confirmed Staff member.',
        );
      }
      return Text(
        widget.awaitingConfirmation
            ? 'After the Manager confirms your Invite, sign in and open this page in each place where you use ER Schedule.'
            : 'After you sign in, open this page in each place where you use ER Schedule.',
      );
    }
    return switch (state) {
      PushState.unsupported => const Text(
        'Notifications are unavailable in this browser. On iPhone or iPad, complete the Home Screen steps below first; notifications require iOS or iPadOS 16.4 or later.',
      ),
      PushState.available => FilledButton.icon(
        onPressed: _busy ? null : _allowNotifications,
        icon: const Icon(Icons.notifications_active_outlined),
        label: const Text('Allow notifications'),
      ),
      PushState.denied => const Text(
        'Notifications are blocked in this place’s browser or app settings.',
      ),
      PushState.enabled => const Text('Notifications can reach this place.'),
    };
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Hear about Schedule changes',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Notifications deliver Change announcements in each place where you allow them.',
        ),
        const SizedBox(height: 16),
        FutureBuilder<PushState>(
          future: _pushState,
          builder: (context, snapshot) => snapshot.hasData
              ? _notificationStep(snapshot.data!)
              : const Center(child: CircularProgressIndicator()),
        ),
        if (_message != null) ...[const SizedBox(height: 8), Text(_message!)],
        if (_installState == browser.InstallState.installed) ...[
          const SizedBox(height: 16),
          const Text('ER Schedule is open as an installed app in this place.'),
        ] else if (_installState == browser.InstallState.available) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _installing ? null : _install,
            icon: const Icon(Icons.install_mobile_outlined),
            label: const Text('Install on this device'),
          ),
        ],
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _copyLink,
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Copy app link'),
        ),
        Text(
          widget.awaitingConfirmation
              ? 'Paste the copied link into a message to yourself, then open it on your computer. After the Manager confirms your Invite, sign in there with the same personal email. Do not reuse the one-time Invite link.'
              : 'Paste the copied link into a message to yourself, then open it on your computer and sign in with the same personal email. Do not reuse a one-time Invite link.',
        ),
        if (_installState != browser.InstallState.installed) ...[
          const SizedBox(height: 20),
          Text(
            'Install on a phone or tablet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(phoneInstallGuidance),
        ],
        const SizedBox(height: 20),
        Text(
          'Install on a computer',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Windows: in Edge, open the Apps menu and choose Install this site as an app. In Chrome, choose Install page as app from the menu.\n\nMac: in Safari, choose File > Add to Dock. In Chrome, choose Install page as app from the menu.',
        ),
        const SizedBox(height: 16),
        const Text(computerInstallFallbackGuidance),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => HelpPage(roles: widget.helpRoles),
            ),
          ),
          icon: const Icon(Icons.help_outline),
          label: const Text('Setup Help'),
        ),
      ],
    ),
  );
}
