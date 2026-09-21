import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Appearance belongs to this device and is available before sign-in.
final appearanceMode = ValueNotifier<ThemeMode>(ThemeMode.system);
const _appearanceKey = 'appearance_mode';

Future<void> loadAppearance() async {
  final preferences = await SharedPreferences.getInstance();
  appearanceMode.value = switch (preferences.getString(_appearanceKey)) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

Future<void> chooseAppearance(ThemeMode mode) async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString(_appearanceKey, mode.name);
  appearanceMode.value = mode;
}

class AppearanceTile extends StatelessWidget {
  const AppearanceTile({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: appearanceMode,
    builder: (context, mode, _) => ListTile(
      leading: const Icon(Icons.brightness_6_outlined),
      title: const Text('Appearance'),
      subtitle: Text(switch (mode) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      }),
      onTap: () => showAppearancePicker(context),
    ),
  );
}

class AppearanceButton extends StatelessWidget {
  const AppearanceButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Appearance',
    icon: const Icon(Icons.brightness_6_outlined),
    onPressed: () => showAppearancePicker(context),
  );
}

Future<void> showAppearancePicker(BuildContext context) async {
  final selected = await showDialog<ThemeMode>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('Appearance on this device'),
      children: [
        for (final choice in ThemeMode.values)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, choice),
            child: Text(switch (choice) {
              ThemeMode.system => 'System',
              ThemeMode.light => 'Light',
              ThemeMode.dark => 'Dark',
            }),
          ),
      ],
    ),
  );
  if (selected != null) await chooseAppearance(selected);
}
