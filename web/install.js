let installPrompt = null;
let installed = false;

window.addEventListener('beforeinstallprompt', (event) => {
  event.preventDefault();
  installPrompt = event;
});

window.addEventListener('appinstalled', () => {
  installPrompt = null;
  installed = true;
});

window.erInstallState = () => {
  if (installed || window.matchMedia('(display-mode: standalone)').matches ||
      navigator.standalone === true) return 'installed';
  return installPrompt ? 'available' : 'unavailable';
};

window.erPromptInstall = async () => {
  if (!installPrompt) return 'unavailable';
  const prompt = installPrompt;
  try {
    await prompt.prompt();
    const choice = await prompt.userChoice;
    return choice.outcome;
  } finally {
    // A BeforeInstallPromptEvent is one-shot, including after dismissal.
    // Clear it after its result has been reported so the caller can direct
    // the user to the manual steps instead of leaving a dead button behind.
    installPrompt = null;
  }
};
