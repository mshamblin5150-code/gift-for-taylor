import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../help/help_page.dart';
import 'install_browser.dart' as browser;

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
    this.awaitingConfirmation = false,
    this.helpRoles = const {HelpRole.staffMember},
  });

  final bool awaitingConfirmation;
  final Set<HelpRole> helpRoles;

  @override
  State<AppSetupPage> createState() => _AppSetupPageState();
}

class _AppSetupPageState extends State<AppSetupPage> {
  Timer? _refresh;
  browser.InstallState _installState = browser.installState();

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
    await browser.promptInstall();
    if (mounted) setState(() => _installState = browser.installState());
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add ER Schedule')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Use ER Schedule on your phone and computer',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Add it separately on each device to get an ER Schedule icon. Your browser will ask you to confirm installation.',
        ),
        if (_installState == browser.InstallState.installed) ...[
          const SizedBox(height: 16),
          const Text(
            'ER Schedule is already open as an installed app on this device.',
          ),
        ] else if (_installState == browser.InstallState.available) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _install,
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
        const SizedBox(height: 20),
        Text(
          'Install on a phone or tablet',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'iPhone or iPad: tap Copy app link and paste it into Safari’s address bar. Tap Share > Add to Home Screen, choose Open as Web App, then tap Add. Open ER Schedule from its Home Screen icon.\n\nAndroid Chrome: tap Install if Chrome offers it, or open Chrome’s menu and choose Install app. Then open the new icon.',
        ),
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
        const Text(
          'If your browser does not offer installation, bookmark the ordinary app link instead.',
        ),
        if (!widget.helpRoles.contains(HelpRole.maintainer)) ...[
          const SizedBox(height: 20),
          Text(
            'Notifications on each device',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            widget.awaitingConfirmation
                ? 'After the Manager confirms your Invite, open Settings > Notifications > Allow notifications on each device. Nothing is enabled while you wait.'
                : 'Open Settings > Notifications > Allow notifications on each device. Choose Allow in the browser or device prompt. If blocked, change permission in that device’s browser or app settings. On iPhone or iPad, notifications require the Home Screen web app on iOS or iPadOS 16.4 or later.',
          ),
        ],
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
