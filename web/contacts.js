// The picker is available only in supporting secure, top-level browsers.
window.erCanPickContact = () =>
  window.isSecureContext && window.top === window &&
  typeof navigator.contacts?.select === 'function';

window.erPickContact = async () => {
  const contacts = await navigator.contacts.select(['name', 'tel'], {
    multiple: false,
  });
  if (!contacts.length) return null;
  const contact = contacts[0];
  return JSON.stringify({
    name: contact.name?.[0] ?? '',
    numbers: contact.tel ?? [],
  });
};

window.erSaveContact = (vCard) => {
  const url = URL.createObjectURL(new Blob([vCard], { type: 'text/vcard;charset=utf-8' }));
  const link = document.createElement('a');
  link.href = url;
  link.download = 'er-schedule-contact.vcf';
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60000);
};
