enum InstallState { installed, available, unavailable }

enum InstallPromptResult { accepted, dismissed, unavailable }

InstallPromptResult installPromptResultFromBrowser(String value) =>
    switch (value) {
      'accepted' => InstallPromptResult.accepted,
      'dismissed' => InstallPromptResult.dismissed,
      _ => InstallPromptResult.unavailable,
    };
