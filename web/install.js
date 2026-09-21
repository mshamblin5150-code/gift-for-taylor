let installPrompt = null;

window.addEventListener('beforeinstallprompt', (event) => {
  event.preventDefault();
  installPrompt = event;
});

window.addEventListener('appinstalled', () => {
  installPrompt = null;
});

window.erInstallState = () => {
  if (window.matchMedia('(display-mode: standalone)').matches ||
      navigator.standalone === true) return 'installed';
  return installPrompt ? 'available' : 'unavailable';
};

window.erPromptInstall = async () => {
  if (!installPrompt) return 'unavailable';
  const prompt = installPrompt;
  installPrompt = null;
  await prompt.prompt();
  const choice = await prompt.userChoice;
  return choice.outcome;
};
